import Stripe from "npm:stripe@22";
Deno.env.set("APP_ORIGIN","https://famunova.invalid");
Deno.env.set("STRIPE_SECRET_KEY","sk_test_fake");
Deno.env.set("SUPABASE_URL","https://supabase.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY","fake");
Deno.env.set("STRIPE_WEBHOOK_SECRET","whsec_fake");
const {createHandler}=await import("../stripe-webhook/index.ts");
const real=new Stripe("sk_test_fake");
const group="20000000-0000-4000-8000-000000000001",owner="10000000-0000-4000-8000-000000000001";
for(const scenario of ["applied","duplicate","retry","live","wrong customer","remote failure"]){
 Deno.test("signed webhook "+scenario,async()=>{
 let applied=0;
 const payload=JSON.stringify({id:"evt_Test",type:"customer.subscription.updated",livemode:scenario==="live",data:{object:{id:"sub_Test"}}});
 const header=await real.webhooks.generateTestHeaderStringAsync({payload,secret:"whsec_fake"});
 const chain={select:()=>chain,eq:()=>chain,single:()=>Promise.resolve({data:{owner_id:scenario==="wrong customer"?group:owner},error:null})};
 const database={from:()=>chain,rpc:(name:string,args:Record<string,unknown>)=>{if(name==="famunova_begin_stripe_observation")return Promise.resolve({data:1,error:null});applied++;if(args.p_group_id!==group||args.p_user_id!==owner||args.p_plan!=="plus")throw Error("Incorrect reconciliation");return Promise.resolve({data:scenario,error:null});}};
 const client={webhooks:real.webhooks,subscriptions:{retrieve:()=>{if(scenario==="remote failure")throw Error("offline");return Promise.resolve({id:"sub_Test",livemode:false,customer:"cus_Test",metadata:{family_group_id:group,supabase_user_id:owner},items:{data:[{price:{id:"price_1UeZokDHyA40vHHZfdf1YLJv"},current_period_end:1800000000}]},status:"active",cancel_at_period_end:false});}}};
 const handler=createHandler({db:()=>database,stripe:()=>client} as unknown as Parameters<typeof createHandler>[0]);
 const response=await handler(new Request("https://famunova.invalid",{method:"POST",headers:{"stripe-signature":header},body:payload}));
 const expected=scenario==="live"?400:scenario==="retry"?503:["wrong customer","remote failure"].includes(scenario)?500:200;
 if(response.status!==expected)throw Error("Unexpected status "+response.status);
 if(applied!==(["applied","duplicate","retry"].includes(scenario)?1:0))throw Error("Unexpected apply count");
 });
}
