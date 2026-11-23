// DRAFT ONLY. Stripe portal is CUSTOMER-WIDE; group selection does not isolate subscriptions.
import {configured,originAllowed,cors,json,db,userFromRequest,stripe,uuid,isOwner,appOrigin} from "../_shared/billing.ts";
Deno.serve(async(req)=>{
 const origin=req.headers.get("Origin")||"";if(!originAllowed(origin))return new Response("Forbidden",{status:403});
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors(origin)});
 if(req.method!=="POST")return json({error:"Method not allowed"},405,origin);
 if(!configured())return json({error:"Test configuration missing"},503,origin);
 try{const user=await userFromRequest(req);if(!user)return json({error:"Unauthorized"},401,origin);
  const body=await req.json();if(!uuid(body?.groupId))return json({error:"groupId required"},400,origin);
  if(!await isOwner(body.groupId,user.id))return json({error:"Not group owner"},403,origin);
  const client=db();const {data:sub,error:subError}=await client.from("billing_subscriptions").select("stripe_subscription_id,stripe_customer_id").eq("group_id",body.groupId).eq("user_id",user.id).limit(1);if(subError)throw subError;
  if(!sub?.length)return json({error:"No subscription for this group"},404,origin);
  const {data:customer,error}=await client.from("billing_customers").select("stripe_customer_id").eq("user_id",user.id).single();if(error)throw error;
  if(sub[0].stripe_customer_id!==customer.stripe_customer_id)throw new Error("Customer mismatch");
  // Block multi-group customers until portal behavior is explicitly approved.
  const {data:all,error:allError}=await client.from("billing_subscriptions").select("group_id").eq("user_id",user.id);if(allError)throw allError;
  if(new Set((all||[]).map(x=>x.group_id)).size>1)return json({error:"Multi-family portal requires review"},409,origin);
  const session=await stripe().billingPortal.sessions.create({customer:customer.stripe_customer_id,return_url:`${appOrigin}/?billing=portal`});
  if(!session.url?.startsWith("https://billing.stripe.com/"))throw new Error("Unexpected portal URL");return json({url:session.url},200,origin);
 }catch(e){console.error("portal",e);return json({error:"Portal failed"},500,origin);}
});
