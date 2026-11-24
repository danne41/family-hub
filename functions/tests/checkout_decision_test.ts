import {checkoutDecision} from "../_shared/checkout-decision.ts";
const base={status:"open",payment_status:"unpaid",subscription:null,url:"https://checkout.stripe.com/test"};
const cases=[
 ["open same price",{},true,"resume"],
 ["different price",{},false,"block"],
 ["expired unpaid",{status:"expired"},true,"release"],
 ["expired paid",{status:"expired",payment_status:"paid"},true,"block"],
 ["expired with subscription",{status:"expired",subscription:"sub_test"},true,"block"],
 ["completed",{status:"complete"},true,"block"],
 ["unknown",{status:null},true,"block"],
 ["foreign URL",{url:"https://foreign.invalid"},true,"block"],
 ["missing URL",{url:null},true,"block"],
 ["open with subscription",{subscription:"sub_test"},true,"block"]
] as const;
for(const [name,patch,same,expected] of cases)Deno.test(name,()=>{const actual=checkoutDecision({...base,...patch},same);if(actual!==expected)throw new Error("Expected "+expected+", got "+actual);});
