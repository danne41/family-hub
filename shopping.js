// Family Hub 0.4: veckohandling med Supabase och familjegrupper.
const el=id=>document.getElementById(id);
const weekStart=d=>{const x=new Date(d.getFullYear(),d.getMonth(),d.getDate(),12);x.setDate(x.getDate()-(x.getDay()+6)%7);return x};
const dateStr=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
const isoWeek=d=>{const x=new Date(Date.UTC(d.getFullYear(),d.getMonth(),d.getDate()));x.setUTCDate(x.getUTCDate()+4-(x.getUTCDay()||7));return Math.ceil((((x-new Date(Date.UTC(x.getUTCFullYear(),0,1)))/86400000)+1)/7)};
let monday=weekStart(new Date()),items=[],loading=false;
const client=()=>window.FH?.client, group=()=>el('shopping-group').value;
const status=t=>el('shopping-status').textContent=t;
const safe=t=>String(t??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function refresh(){
 const c=client(),g=group();el('shopping-week').textContent=`v. ${isoWeek(monday)} · ${monday.getFullYear()}`;
 if(!c||!window.FH?.user||!g){items=[];render();status('Skapa eller gå med i en familjegrupp under Konto & grupper.');return;}
 loading=true;status('Hämtar inköpslista…');
 const {data,error}=await c.from('shopping_items').select('id,name,done,created_at').eq('group_id',g).eq('week_start',dateStr(monday)).order('created_at');
 loading=false;if(error){status('Kunde inte hämta listan: '+error.message);return;}items=data||[];status('');render();
}
function render(){const box=el('shopping-items');box.replaceChildren();if(!items.length){box.textContent='Inga varor för den här veckan.';return;}
 for(const item of items){const row=document.createElement('div');row.className='entry';const left=document.createElement('div');left.className='entry-left';const cb=document.createElement('input');cb.type='checkbox';cb.checked=item.done;cb.setAttribute('aria-label','Markera '+item.name);cb.onchange=async()=>{const {error}=await client().from('shopping_items').update({done:cb.checked}).eq('id',item.id);if(error){status(error.message);cb.checked=!cb.checked;}else refresh()};const name=document.createElement('strong');name.textContent=item.name;if(item.done)name.style.textDecoration='line-through';left.append(cb,name);const del=document.createElement('button');del.className='remove';del.textContent='Ta bort';del.onclick=async()=>{const {error}=await client().from('shopping_items').delete().eq('id',item.id);if(error)status(error.message);else refresh()};row.append(left,del);box.append(row)}
}
window.renderSharedShopping=render;
function groupsChanged(){const select=el('shopping-group'),old=select.value;select.replaceChildren();for(const g of window.FH?.groups||[]){const o=document.createElement('option');o.value=g.id;o.textContent=g.name;select.append(o)}if([...select.options].some(o=>o.value===old))select.value=old;refresh()}
document.addEventListener('fh-groups',groupsChanged);
el('shopping-group').onchange=refresh;
el('shopping-prev').onclick=()=>{monday.setDate(monday.getDate()-7);refresh()};
el('shopping-next').onclick=()=>{monday.setDate(monday.getDate()+7);refresh()};
el('shopping-form').onsubmit=async e=>{e.preventDefault();if(!group()||loading)return;const name=String(new FormData(e.currentTarget).get('item')||'').trim();if(!name)return;const {error}=await client().from('shopping_items').insert({group_id:group(),week_start:dateStr(monday),name,created_by:window.FH.user.id});if(error)status('Kunde inte lägga till: '+error.message);else{e.currentTarget.reset();refresh()}};
el('shopping-copy').onclick=async()=>{if(!group())return;const prev=new Date(monday);prev.setDate(prev.getDate()-7);const {data,error}=await client().from('shopping_items').select('name').eq('group_id',group()).eq('week_start',dateStr(prev));if(error)return status(error.message);const names=(data||[]).map(x=>x.name);const missing=names.filter(n=>!items.some(i=>i.name.toLocaleLowerCase('sv')===n.toLocaleLowerCase('sv')));if(!missing.length)return status('Inga nya varor att kopiera.');const {error:insertError}=await client().from('shopping_items').insert(missing.map(name=>({name,group_id:group(),week_start:dateStr(monday),created_by:window.FH.user.id})));if(insertError)status(insertError.message);else refresh()};
el('shopping-clear').onclick=async()=>{if(!group()||!items.length||!confirm('Radera alla varor i denna vecka?'))return;const {error}=await client().from('shopping_items').delete().eq('group_id',group()).eq('week_start',dateStr(monday));if(error)status(error.message);else refresh()};
groupsChanged();
