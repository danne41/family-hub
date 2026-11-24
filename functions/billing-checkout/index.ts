// DRAFT ONLY: Supabase test project. No production deployment.
import {appOrigin,configured,originAllowed,cors,json,db,userFromRequest,priceMap,stripe,uuid,isOwner} from "../_shared/billing.ts";
import {checkoutDecision} from "../_shared/checkout-decision.ts";
export function createHandler(deps={db,stripe,userFromRequest,isOwner}){
 return async function handler(req:Request):Promise<Response>{
 const origin=req.headers.get("Origin")||"";
 if(!originAllowed(origin))return new Response("Forbidden",{status:403});
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors(origin)});
 if(req.method!=="POST")return json({error:"Method not allowed"},405,origin);
 if(!configured())return json({error:"Test configuration missing"},503,origin);
 try{
  const user=await deps.userFromRequest(req);if(!user)return json({error:"Unauthorized"},401,origin);
  const body=await req.json();const groupId=body?.groupId,priceId=body?.priceId;
  if(!uuid(groupId)||typeof priceId!=="string"||!Object.hasOwn(priceMap,priceId))return json({error:"Invalid group or price"},400,origin);
  if(!await deps.isOwner(groupId,user.id))return json({error:"Only group owner may subscribe"},403,origin);
  const client=deps.db();const {data:active,error:activeError}=await client.from("billing_subscriptions").select("stripe_subscription_id").eq("group_id",groupId).in("status",["active","trialing","past_due","unpaid","incomplete","paused"]).limit(1);
  if(activeError)throw activeError;
  if(active?.length)return json({error:"Group already has a subscription"},409,origin);
  const stripeClient=deps.stripe();const {data:existing,error:customerError}=await client.from("famunova_family_billing_customers").select("stripe_customer_id").eq("group_id",groupId).eq("owner_id",user.id).maybeSingle();if(customerError)throw customerError;
  let customerId=existing?.stripe_customer_id;
  if(!customerId){const customer=await stripeClient.customers.create({email:user.email||undefined,metadata:{supabase_user_id:user.id,family_group_id:groupId}},{idempotencyKey:`famunova-test-family-customer-${groupId}`});customerId=customer.id;
   const {error}=await client.rpc("famunova_bind_family_customer",{p_group:groupId,p_owner:user.id,p_customer:customerId});if(error)throw error;}
  // Atomically reserve this family BEFORE creating a Stripe Checkout Session.
  // Reservations remain blocked until Stripe confirms a terminal unpaid session.
  const {data:pending,error:pendingError}=await client.from("famunova_checkout_reservations").select("reservation_key,stripe_session_id,owner_id,price_id").eq("group_id",groupId).maybeSingle();
  if(pendingError)throw pendingError;
  if(pending){
   if(pending.owner_id!==user.id)return json({error:"Checkout requires reconciliation"},409,origin);
   let sessionId=pending.stripe_session_id;
   if(!sessionId){
    // Recover only an existing session; never recreate an ambiguous request.
    const matches:string[]=[];
    for await(const candidate of stripeClient.checkout.sessions.list({customer:customerId,limit:100})){
     if(candidate.metadata?.reservation_key===pending.reservation_key)matches.push(candidate.id);
     if(matches.length>1)break;
    }
    if(matches.length!==1)return json({error:"Checkout requires reconciliation"},409,origin);
    sessionId=matches[0];
   }
   const previous=await stripeClient.checkout.sessions.retrieve(sessionId);
   const previousCustomer=typeof previous.customer==="string"?previous.customer:previous.customer?.id;
   if(previous.livemode||previousCustomer!==customerId||previous.metadata?.family_group_id!==groupId||previous.metadata?.supabase_user_id!==user.id||previous.metadata?.reservation_key!==pending.reservation_key)return json({error:"Checkout requires reconciliation"},409,origin);
   if(!pending.stripe_session_id){
    const {data:recovered,error:recoverError}=await client.rpc("famunova_bind_checkout_session",{p_group:groupId,p_key:pending.reservation_key,p_session:previous.id});
    if(recoverError)throw recoverError;
    if(recovered!==true)return json({error:"Checkout state changed"},409,origin);
   }
   const decision=checkoutDecision(previous,pending.price_id===priceId);
   if(decision==="resume")return json({url:previous.url},200,origin);
   if(decision!=="release")return json({error:"Previous checkout not safely expired"},409,origin);
   const {data:released,error:releaseError}=await client.rpc("famunova_release_expired_checkout",{p_group:groupId,p_key:pending.reservation_key,p_session:previous.id});
   if(releaseError)throw releaseError;
   if(released!==true)return json({error:"Checkout state changed"},409,origin);
  }
  const reservationKey=crypto.randomUUID();
  const {data:admission,error:reservationError}=await client.rpc("famunova_reserve_checkout_internal",
   {p_group_id:groupId,p_owner_id:user.id,p_price_id:priceId,p_key:reservationKey});
  if(reservationError)throw reservationError;
  if(admission!=="acquired")return json({error:admission==="subscribed"?"Group already subscribed":"Checkout already pending for this family"},409,origin);
  const session=await stripeClient.checkout.sessions.create({mode:"subscription",customer:customerId,line_items:[{price:priceId,quantity:1}],client_reference_id:user.id,metadata:{supabase_user_id:user.id,family_group_id:groupId,reservation_key:reservationKey},subscription_data:{metadata:{supabase_user_id:user.id,family_group_id:groupId}},success_url:`${appOrigin}/?billing=success`,cancel_url:`${appOrigin}/?billing=cancel`,allow_promotion_codes:false,expires_at:Math.floor(Date.now()/1000)+1800},{idempotencyKey:`famunova-checkout-${reservationKey}`});
  if(session.livemode)throw new Error("Unexpected live session");
  const {data:bound,error:bindError}=await client.rpc("famunova_bind_checkout_session",{p_group:groupId,p_key:reservationKey,p_session:session.id});
  if(bindError||bound!==true)throw new Error("Session binding failed");
  if(!session.url||!session.url.startsWith("https://checkout.stripe.com/"))throw new Error("Unexpected checkout URL");
  return json({url:session.url},200,origin);
 }catch(error){console.error("checkout",error);return json({error:"Checkout failed"},500,origin);}
}
}
export const handler=createHandler();
if(import.meta.main)Deno.serve(handler);
