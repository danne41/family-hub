// DRAFT ONLY: Supabase test project. No production deployment.
import {appOrigin,configured,originAllowed,cors,json,db,userFromRequest,priceMap,stripe,uuid,isOwner} from "../_shared/billing.ts";
Deno.serve(async(req)=>{
 const origin=req.headers.get("Origin")||"";
 if(!originAllowed(origin))return new Response("Forbidden",{status:403});
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors(origin)});
 if(req.method!=="POST")return json({error:"Method not allowed"},405,origin);
 if(!configured())return json({error:"Test configuration missing"},503,origin);
 try{
  const user=await userFromRequest(req);if(!user)return json({error:"Unauthorized"},401,origin);
  const body=await req.json();const groupId=body?.groupId,priceId=body?.priceId;
  if(!uuid(groupId)||typeof priceId!=="string"||!priceMap[priceId])return json({error:"Invalid group or price"},400,origin);
  if(!await isOwner(groupId,user.id))return json({error:"Only group owner may subscribe"},403,origin);
  const client=db();const {data:active,error:activeError}=await client.from("billing_subscriptions").select("stripe_subscription_id").eq("group_id",groupId).in("status",["active","trialing","past_due","unpaid","incomplete"]).limit(1);
  if(activeError)throw activeError;
  if(active?.length)return json({error:"Group already has a subscription"},409,origin);
  const stripeClient=stripe();const {data:existing,error:customerError}=await client.from("billing_customers").select("stripe_customer_id").eq("user_id",user.id).maybeSingle();if(customerError)throw customerError;
  let customerId=existing?.stripe_customer_id;
  if(!customerId){const customer=await stripeClient.customers.create({email:user.email||undefined,metadata:{supabase_user_id:user.id}},{idempotencyKey:`famunova-test-customer-${user.id}`});customerId=customer.id;
   const {error}=await client.from("billing_customers").upsert({user_id:user.id,stripe_customer_id:customerId},{onConflict:"user_id"});if(error)throw error;}
  const session=await stripeClient.checkout.sessions.create({mode:"subscription",customer:customerId,line_items:[{price:priceId,quantity:1}],client_reference_id:user.id,metadata:{supabase_user_id:user.id,family_group_id:groupId},subscription_data:{metadata:{supabase_user_id:user.id,family_group_id:groupId}},success_url:`${appOrigin}/?billing=success`,cancel_url:`${appOrigin}/?billing=cancel`,allow_promotion_codes:false});
  if(!session.url||!session.url.startsWith("https://checkout.stripe.com/"))throw new Error("Unexpected checkout URL");
  return json({url:session.url},200,origin);
 }catch(error){console.error("checkout",error);return json({error:"Checkout failed"},500,origin);}
});
