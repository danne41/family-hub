Deno.env.set("APP_ORIGIN","https://famunova.invalid");
Deno.env.set("STRIPE_SECRET_KEY","sk_test_fake");
Deno.env.set("SUPABASE_URL","https://supabase.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY","fake");
const {createHandler}=await import("../billing-checkout/index.ts");
const group="20000000-0000-4000-8000-000000000001",owner="10000000-0000-4000-8000-000000000001",price="price_1UeZokDHyA40vHHZfdf1YLJv";
type Deps=NonNullable<Parameters<typeof createHandler>[0]>;
for(const scenario of ["not owner","database failure","reservation busy","stripe failure","binding failure","unknown session","success"]){
 Deno.test("checkout "+scenario,async()=>{
 let creates=0;const calls:string[]=[];
 const db={from(table:string){const result=table==="billing_subscriptions"?{data:[],error:scenario==="database failure"?new Error("offline"):null}:table==="famunova_family_billing_customers"?{data:{stripe_customer_id:"cus_Test"},error:null}:{data:scenario==="unknown session"?{owner_id:owner,reservation_key:"key",stripe_session_id:null,price_id:price}:null,error:null};const chain={select:()=>chain,eq:()=>chain,in:()=>chain,limit:()=>Promise.resolve(result),maybeSingle:()=>Promise.resolve(result)};return chain;},rpc(name:string){calls.push(name);return Promise.resolve({data:name==="famunova_reserve_checkout_internal"?(scenario==="reservation busy"?"reserved":"acquired"):scenario!=="binding failure",error:null});}};
 const stripe={checkout:{sessions:{async *list(){},create(){creates++;if(scenario==="stripe failure")throw new Error("offline");return Promise.resolve({id:"cs_test_Test",livemode:false,url:"https://checkout.stripe.com/test"});}}}};
 const handler=createHandler({db:()=>db,stripe:()=>stripe,userFromRequest:()=>Promise.resolve({id:owner}),isOwner:()=>Promise.resolve(scenario!=="not owner")} as unknown as Deps);
 const response=await handler(new Request("https://famunova.invalid",{method:"POST",headers:{Origin:"https://famunova.invalid"},body:JSON.stringify({groupId:group,priceId:price})}));
 const expected=scenario==="success"?200:scenario==="not owner"?403:["reservation busy","unknown session"].includes(scenario)?409:500;
 if(response.status!==expected)throw new Error("Unexpected status "+response.status);
 const expectedCreates=["stripe failure","binding failure","success"].includes(scenario)?1:0;
 if(creates!==expectedCreates)throw new Error("Unexpected Stripe creation count "+creates);
 if(calls.includes("famunova_release_expired_checkout"))throw new Error("Unsafe release");
 if(expectedCreates&&calls[0]!=="famunova_reserve_checkout_internal")throw new Error("Creation without reservation");
 });
}
