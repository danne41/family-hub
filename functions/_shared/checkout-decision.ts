// Pure decision logic for a previously verified checkout session.
export function checkoutDecision(session:{status:string|null;payment_status:string;subscription:unknown;url?:string|null},samePrice:boolean):"resume"|"release"|"block"{
 if(samePrice&&session.status==="open"&&session.payment_status==="unpaid"&&!session.subscription&&session.url?.startsWith("https://checkout.stripe.com/"))return "resume";
 if(session.status==="expired"&&session.payment_status==="unpaid"&&!session.subscription)return "release";
 return "block";
}
