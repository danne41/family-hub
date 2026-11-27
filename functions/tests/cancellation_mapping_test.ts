import { endsAtPeriodEnd } from "../stripe-webhook/index.ts";
const end = 1798392651;
Deno.test("flexible billing cancellation at period end", () => {
 if (!endsAtPeriodEnd({cancel_at:end,cancel_at_period_end:false},end)) throw new Error("scheduled cancellation lost");
});
Deno.test("legacy period end cancellation", () => {
 if (!endsAtPeriodEnd({cancel_at:null,cancel_at_period_end:true},end)) throw new Error("legacy cancellation lost");
});
Deno.test("withdrawn cancellation", () => {
 if (endsAtPeriodEnd({cancel_at:null,cancel_at_period_end:false},end)) throw new Error("cancellation retained");
});
Deno.test("custom cancellation date is not period end", () => {
 if (endsAtPeriodEnd({cancel_at:end-86400,cancel_at_period_end:false},end)) throw new Error("custom date mislabeled");
});
Deno.test("missing period end is not a match", () => {
 if (endsAtPeriodEnd({cancel_at:end,cancel_at_period_end:false},undefined)) throw new Error("missing period end accepted");
});
