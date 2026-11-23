import Stripe from "npm:stripe@22";
import { createClient } from "npm:@supabase/supabase-js@2";
export const priceMap: Record<string,{plan:string; interval:string}> = {
 "price_1UeZokDHyA40vHHZfdf1YLJv":{plan:"plus",interval:"month"},
 "price_1UeZrDDHyA40vHHZNtj3nqLS":{plan:"plus",interval:"year"},
 "price_1UeZsrDHyA40vHHZHasgi7rX":{plan:"premium_family",interval:"month"},
 "price_1UeZu9DHyA40vHHZKanc2Yhx":{plan:"premium_family",interval:"year"},
};
export const appOrigin=(Deno.env.get("APP_ORIGIN")||"").replace(/\/$/,"");
export const key=Deno.env.get("STRIPE_SECRET_KEY")||"";
export const url=Deno.env.get("SUPABASE_URL")||"";
export const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
export function configured(){return !!appOrigin && key.startsWith("sk_test_") && !!url && !!serviceKey;}
export function originAllowed(origin:string){return origin===appOrigin && !!appOrigin;}
export function cors(origin:string){return {"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Headers":"authorization,apikey,x-client-info,content-type","Access-Control-Allow-Methods":"POST,OPTIONS","Vary":"Origin"};}
export function json(body:unknown,status:number,origin:string){return new Response(JSON.stringify(body),{status,headers:{...cors(origin),"Content-Type":"application/json","Cache-Control":"no-store"}});}
export function db(){return createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});}
export async function userFromRequest(req:Request){const match=/^Bearer\s+(.+)$/i.exec(req.headers.get("Authorization")||"");if(!match)return null;const {data,error}=await db().auth.getUser(match[1]);return error?null:data.user;}
export function stripe(){return new Stripe(key);}
export function uuid(value:unknown):value is string{return typeof value==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);}
export async function isOwner(groupId:string,userId:string){const {data,error}=await db().from("family_groups").select("id,owner_id").eq("id",groupId).maybeSingle();if(error)throw error;return data?.owner_id===userId;}
