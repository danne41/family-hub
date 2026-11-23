// DRAFT ONLY: manual/scheduled reconciliation for subscriptions already recorded in DB.
// Deploy only in an isolated test environment with a private scheduler token.
import {configured,db,stripe,priceMap,uuid} from "../_shared/billing.ts";
const token=Deno.env.get("BILLING_RECONCILE_TOKEN")||"";
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 const bearer=/^Bearer (.+)$/.exec(req.headers.get("Authorization")||"");
 if(!configured()||token.length<32)return new Response("Not configured",{status:503});
 // Compare secrets without short-circuiting character differences.
 const input=bearer?.[1]||"";
 const a=new TextEncoder().encode(input),b=new TextEncoder().encode(token);
 let diff=a.length^b.length;
 for(let i=0;i<Math.max(a.length,b.length);i++)diff|=(a[i]||0)^(b[i]||0);
 if(diff!==0)return new Response("Unauthorized",{status:401});
 try{
  const database=db(),stripeClient=stripe();
  // Stable keyset pagination: updated_at changes during reconciliation, so never page by it.
  // The authenticated caller must carry nextCursor into the next invocation.
  let payload:unknown;
  try{payload=await req.json();}catch{return new Response("Invalid JSON",{status:400});}
  const cursor=(payload && typeof payload==="object" && "cursor" in payload)?(payload as {cursor:unknown}).cursor:null;
  if(cursor!==null && (typeof cursor!=="string" || !/^sub_[A-Za-z0-9]+$/.test(cursor)))
   return new Response("Invalid cursor",{status:400});
  let query=database.from("billing_subscriptions")
   .select("stripe_subscription_id,user_id,group_id,stripe_customer_id")
   .not("group_id","is",null).order("stripe_subscription_id",{ascending:true}).limit(26);
  if(cursor)query=query.gt("stripe_subscription_id",cursor);
  const {data,error}=await query;
  if(error)throw error;
  const batch=(data||[]).slice(0,25);
  const hasMore=(data||[]).length>25;
  const nextCursor=hasMore?batch[batch.length-1].stripe_subscription_id:null;
  let updated=0,failed=0,skipped=0;
  for(const row of batch){
   try{
    if(!uuid(row.group_id)||!uuid(row.user_id)){skipped++;continue;}
    const observedAt=new Date().toISOString();
    const sub=await stripeClient.subscriptions.retrieve(row.stripe_subscription_id);
    const groupId=sub.metadata?.family_group_id,userId=sub.metadata?.supabase_user_id;
    const customerId=typeof sub.customer==="string"?sub.customer:sub.customer.id;
    if(groupId!==row.group_id||userId!==row.user_id||customerId!==row.stripe_customer_id)
     throw new Error("Subscription identity mismatch");
    const item=sub.items.data[0];
    if(sub.items.data.length!==1||!item||!Object.hasOwn(priceMap,item.price.id))throw new Error("Unapproved price");
    const plan=priceMap[item.price.id];
    const {error:rpcError}=await database.rpc("famunova_reconcile_stripe_subscription",{
     p_event_id:"reconcile:"+crypto.randomUUID(),p_observed_at:observedAt,
     p_subscription_id:sub.id,p_user_id:userId,p_group_id:groupId,
     p_customer_id:customerId,p_price_id:item.price.id,p_plan:plan.plan,
     p_interval:plan.interval,p_status:sub.status,
     p_period_end:item.current_period_end?new Date(item.current_period_end*1000).toISOString():null,
     p_cancel_at_period_end:sub.cancel_at_period_end
    });
    if(rpcError)throw rpcError;
    updated++;
   }catch(e){failed++;console.error("reconcile subscription",row.stripe_subscription_id,e);}
  }
  return new Response(JSON.stringify({checked:batch.length,updated,failed,skipped,nextCursor,hasMore}),{
   status:failed?503:200,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
 }catch(e){console.error("reconcile batch",e);return new Response("Retry later",{status:503});}
});
