Deno.env.set("APP_ORIGIN","https://famunova.invalid");
Deno.env.set("STRIPE_SECRET_KEY","sk_test_fake");
Deno.env.set("SUPABASE_URL","https://supabase.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY","fake");
Deno.env.set("STRIPE_WEBHOOK_SECRET","whsec_fake");
const checkout=(await import("../billing-checkout/index.ts")).handler;
const portal=(await import("../billing-portal/index.ts")).handler;
const webhook=(await import("../stripe-webhook/index.ts")).handler;
function equal(actual:unknown,expected:unknown){if(actual!==expected)throw new Error(`Expected ${expected}, got ${actual}`);}
const origin="https://famunova.invalid";
for(const [name,handler] of [["checkout",checkout],["portal",portal]] as const){
 Deno.test(name+" rejects foreign origin",async()=>equal((await handler(new Request(origin,{method:"POST",headers:{Origin:"https://foreign.invalid"}}))).status,403));
 Deno.test(name+" accepts preflight",async()=>{const r=await handler(new Request(origin,{method:"OPTIONS",headers:{Origin:origin}}));equal(r.status,204);equal(r.headers.get("Access-Control-Allow-Origin"),origin);});
 Deno.test(name+" rejects GET",async()=>equal((await handler(new Request(origin,{headers:{Origin:origin}}))).status,405));
 Deno.test(name+" rejects missing authentication",async()=>equal((await handler(new Request(origin,{method:"POST",headers:{Origin:origin}}))).status,401));
}
Deno.test("webhook rejects GET",async()=>equal((await webhook(new Request(origin))).status,405));
Deno.test("webhook rejects missing signature",async()=>equal((await webhook(new Request(origin,{method:"POST"}))).status,400));
Deno.test("webhook rejects invalid signature",async()=>equal((await webhook(new Request(origin,{method:"POST",headers:{"stripe-signature":"invalid"},body:"{}"}))).status,400));
