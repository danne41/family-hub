// TEST ONLY. Customer identity is isolated per family by migration 013.
import {configured,originAllowed,cors,json,db,userFromRequest,stripe,uuid,isOwner,appOrigin} from "../_shared/billing.ts";
export async function handler(req:Request):Promise<Response>{
 const origin=req.headers.get("Origin")||"";if(!originAllowed(origin))return new Response("Forbidden",{status:403});
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors(origin)});
 if(req.method!=="POST")return json({error:"Method not allowed"},405,origin);
 if(!configured())return json({error:"Test configuration missing"},503,origin);
 try{const user=await userFromRequest(req);if(!user)return json({error:"Unauthorized"},401,origin);
  const body=await req.json();if(!uuid(body?.groupId))return json({error:"groupId required"},400,origin);
  if(!await isOwner(body.groupId,user.id))return json({error:"Not group owner"},403,origin);
  const client=db();const {data:sub,error:subError}=await client.from("billing_subscriptions").select("stripe_subscription_id,stripe_customer_id").eq("group_id",body.groupId).eq("user_id",user.id).limit(1);if(subError)throw subError;
  if(!sub?.length)return json({error:"No subscription for this group"},404,origin);
  const {data:customer,error}=await client.from("famunova_family_billing_customers").select("stripe_customer_id").eq("group_id",body.groupId).eq("owner_id",user.id).single();if(error)throw error;
  if(sub[0].stripe_customer_id!==customer.stripe_customer_id)throw new Error("Customer mismatch");
  // Block multi-group customers until portal behavior is explicitly approved.
  const {data:all,error:allError}=await client.from("billing_subscriptions").select("group_id").eq("stripe_customer_id",customer.stripe_customer_id);if(allError)throw allError;
  if(new Set((all||[]).map(x=>x.group_id)).size>1)return json({error:"Multi-family portal requires review"},409,origin);
  // Fail closed if Stripe has any subscription outside the selected family,
  // including subscriptions not yet recorded by our webhook.
  const stripeClient=stripe();
  const remoteCustomer=await stripeClient.customers.retrieve(customer.stripe_customer_id);
  if(remoteCustomer.deleted||remoteCustomer.livemode||remoteCustomer.metadata?.family_group_id!==body.groupId||remoteCustomer.metadata?.supabase_user_id!==user.id)return json({error:"Customer reconciliation required"},409,origin);
  let matched=false;
  for await(const remote of stripeClient.subscriptions.list({customer:customer.stripe_customer_id,status:"all",limit:100})){
   if(remote.livemode||remote.metadata?.family_group_id!==body.groupId||remote.metadata?.supabase_user_id!==user.id)return json({error:"Multi-family or unknown Stripe subscription requires review"},409,origin);
   if(remote.id===sub[0].stripe_subscription_id)matched=true;
  }
  if(!matched)return json({error:"Subscription reconciliation required"},409,origin);
  const session=await stripeClient.billingPortal.sessions.create({customer:customer.stripe_customer_id,return_url:`${appOrigin}/?billing=portal`});
  if(!session.url?.startsWith("https://billing.stripe.com/"))throw new Error("Unexpected portal URL");return json({url:session.url},200,origin);
 }catch(e){console.error("portal",e);return json({error:"Portal failed"},500,origin);}
}
if(import.meta.main)Deno.serve(handler);
