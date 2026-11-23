// DRAFT ONLY: requires 004, 006 and 008 migrations in isolated test database.
import Stripe from "npm:stripe@22";
import {configured,db,key,stripe,priceMap,uuid} from "../_shared/billing.ts";
const secret=Deno.env.get("STRIPE_WEBHOOK_SECRET")||"";
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 if(!configured()||!secret.startsWith("whsec_"))return new Response("Not configured",{status:503});
 const signature=req.headers.get("stripe-signature");if(!signature)return new Response("Missing signature",{status:400});
 const client=stripe();let event:Stripe.Event;
 try{event=await client.webhooks.constructEventAsync(await req.text(),signature,secret);}catch{return new Response("Invalid signature",{status:400});}
 const types=["checkout.session.completed","customer.subscription.created","customer.subscription.updated","customer.subscription.deleted"];
 if(!types.includes(event.type))return new Response("ok");
 try{
  let subscriptionId:string;
  if(event.type==="checkout.session.completed"){
   const session=event.data.object as Stripe.Checkout.Session;
   if(session.mode!=="subscription"||!session.subscription)return new Response("ok");
   subscriptionId=typeof session.subscription==="string"?session.subscription:session.subscription.id;
  }else subscriptionId=(event.data.object as Stripe.Subscription).id;
  // Always fetch current Stripe state, including after deletion, rather than trusting stale event snapshots.
  // Timestamp before network retrieval: later-started Stripe observations win.
  const observedAt=new Date().toISOString();
  const sub=await client.subscriptions.retrieve(subscriptionId);
  const groupId=sub.metadata?.family_group_id,userId=sub.metadata?.supabase_user_id;
  if(!uuid(groupId)||!uuid(userId))throw new Error("Missing verified group metadata");
  const customerId=typeof sub.customer==="string"?sub.customer:sub.customer.id;
  const database=db();const {data:owner,error:ownerError}=await database.from("billing_customers").select("user_id").eq("stripe_customer_id",customerId).single();
  if(ownerError||owner.user_id!==userId)throw new Error("Customer mismatch");
  const item=sub.items.data[0];if(sub.items.data.length!==1||!item)throw new Error("Unexpected subscription items");
  const plan=Object.hasOwn(priceMap,item.price.id)?priceMap[item.price.id]:null;if(!plan)throw new Error("Unapproved Stripe price");
  const {data,error}=await database.rpc("famunova_reconcile_stripe_subscription",{p_event_id:event.id,p_observed_at:observedAt,p_subscription_id:sub.id,p_user_id:userId,p_group_id:groupId,p_customer_id:customerId,p_price_id:item.price.id,p_plan:plan.plan,p_interval:plan.interval,p_status:sub.status,p_period_end:item.current_period_end?new Date(item.current_period_end*1000).toISOString():null,p_cancel_at_period_end:sub.cancel_at_period_end});
  if(error)throw error;
  return new Response("ok",{status:200});
 }catch(error){console.error("stripe webhook",error);return new Response("Retry later",{status:500});}
});
