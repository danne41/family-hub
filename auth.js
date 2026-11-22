// Family Hub 0.3 – konton och gruppmedlemskap. Kalendrar är ännu lokala.
const $ = id => document.getElementById(id);
const config = window.FAMILY_HUB_SUPABASE || {};
const configured = /^https:\/\/[^/]+\.supabase\.co$/.test(config.url || '') && !!config.anonKey;
let client, user;
function message(text) { $('auth-info').textContent = text; }
function errText(error) { return error?.message || 'Ett oväntat fel inträffade.'; }
function setUser(u) {
  user=u; $('welcome').classList.toggle('hidden',!!u); $('app-shell').classList.toggle('hidden',!u); $('auth-guest').classList.toggle('hidden',!!u); $('auth-user').classList.toggle('hidden',!u);
  $('groups-panel').classList.toggle('hidden',!u);
  $('signed-in-as').textContent=u ? 'Inloggad som '+(u.email || 'användare') : '';
  $('account-pill').textContent=u ? 'Inloggad · '+(u.email || '') : 'Lokal prototyp · Ej inloggad';
  if(u) refreshGroups(); else $('group-list').replaceChildren();
}
async function refreshGroups(){
  const {data,error}=await client.from('family_groups').select('id,name,created_at,owner_id').order('created_at',{ascending:false});
  if(error){message('Kunde inte hämta grupper: '+errText(error));return;}
  const container=$('group-list');container.replaceChildren();
  if(!data?.length){const p=document.createElement('p');p.className='muted';p.textContent='Du tillhör ännu ingen grupp.';container.append(p);return;}
  for(const g of data){
    const row=document.createElement('div');row.className='entry';
    const title=document.createElement('strong');title.textContent=g.name;row.append(title);
    if(g.owner_id===user.id){const btn=document.createElement('button');btn.className='secondary';btn.textContent='Skapa inbjudningskod';btn.addEventListener('click',async()=>{
      btn.disabled=true;try{const {data:code,error}=await client.rpc('create_group_invite',{p_group_id:g.id});if(error)throw error;
      const shown=window.prompt('Kopiera inbjudningskoden (visas bara nu):',code);if(shown===null)message('Inbjudningskod skapad. Den visas inte igen.');
      }catch(e){message(errText(e));}finally{btn.disabled=false;}
    });row.append(btn);}
    container.append(row);
  }
}
async function init(){
  $('groups-panel').classList.add('hidden');
  if(!configured){$('welcome-message').textContent='Anslutningen är inte konfigurerad.';message('Inloggning är inte aktiverad. Fyll i Supabase Project URL och publishable/anon key i config.js.');$('auth-form').querySelectorAll('button,input').forEach(el=>el.disabled=true);return;}
  try{let createClient; try { ({createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm')); } catch(firstError) { ({createClient}=await import('https://esm.sh/@supabase/supabase-js@2')); } client=createClient(config.url,config.anonKey);
    const {data:{session}}=await client.auth.getSession();setUser(session?.user || null);
    client.auth.onAuthStateChange((_event,session)=>{setTimeout(()=>setUser(session?.user || null),0);});
  }catch(e){const txt='Kunde inte starta inloggning. Kontrollera nätverket och att Supabase kan nås. '+errText(e);message(txt);$('welcome-message').textContent=txt;return;}
  let registration=false;
  const submit=$('welcome-submit'), welcomeMsg=$('welcome-message'), wf=$('welcome-form');
  function mode(isRegister){registration=isRegister;$('tab-login').classList.toggle('chosen',!registration);$('tab-register').classList.toggle('chosen',registration);$('welcome-title').textContent=registration?'Skapa ditt konto':'Välkommen tillbaka';$('welcome-subtitle').textContent=registration?'Börja med ett konto. Sedan kan du skapa eller gå med i en familjegrupp.':'Logga in för att öppna Family Hub.';submit.textContent=registration?'Skapa konto':'Logga in';wf.elements.password.autocomplete=registration?'new-password':'current-password';welcomeMsg.textContent='';}
  $('tab-login').addEventListener('click',()=>mode(false));$('tab-register').addEventListener('click',()=>mode(true));
  wf.addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(wf),email=String(f.get('email')||'').trim(),password=String(f.get('password')||'');if(!email||password.length<8){welcomeMsg.textContent='Ange en e-postadress och ett lösenord med minst åtta tecken.';return;}
    submit.disabled=true;welcomeMsg.textContent=registration?'Skapar konto…':'Loggar in…';try{
      if(registration){const {data,error}=await client.auth.signUp({email,password,options:{emailRedirectTo:window.location.origin+window.location.pathname}});if(error)throw error;welcomeMsg.textContent=data.session?'Kontot skapat.':'Kontrollera din e-post och bekräfta kontot. Återvänd sedan hit och logga in.';}
      else{const {error}=await client.auth.signInWithPassword({email,password});if(error)throw error;welcomeMsg.textContent='Inloggad.';}
    }catch(err){welcomeMsg.textContent='Det gick inte att '+(registration?'skapa konto':'logga in')+': '+errText(err)+'. Om det står Load failed, kontrollera Supabase-adressen, Safari-nätverket och eventuella innehållsblockerare.';}finally{submit.disabled=false;}
  });
  $('auth-form').addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(e.currentTarget);
    const {error}=await client.auth.signInWithPassword({email:String(f.get('email')).trim(),password:String(f.get('password'))});
    message(error?'Inloggning misslyckades: '+errText(error):'Inloggad.');
  });
  $('signup').addEventListener('click',async()=>{const f=new FormData($('auth-form'));const email=String(f.get('email')).trim(),password=String(f.get('password'));
    if(!email||password.length<8){message('Ange e-postadress och minst åtta tecken i lösenordet.');return;}
    const {error}=await client.auth.signUp({email,password});message(error?'Kunde inte skapa konto: '+errText(error):'Kontot har registrerats. Kontrollera e-posten för eventuell bekräftelselänk.');
  });
  $('signout').addEventListener('click',async()=>{const {error}=await client.auth.signOut();if(error)message(errText(error));});
  $('create-group-form').addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(e.currentTarget),name=String(f.get('name')).trim();if(!name)return;
    const {error}=await client.rpc('create_family_group',{p_name:name});if(error)message(errText(error));else{e.target.reset();message('Gruppen skapades.');await refreshGroups();}
  });
  $('join-group-form').addEventListener('submit',async e=>{e.preventDefault();const code=String(new FormData(e.currentTarget).get('code')).trim();
    const {error}=await client.rpc('join_family_group',{p_code:code});if(error)message('Kunde inte gå med: '+errText(error));else{e.target.reset();message('Du är nu medlem i gruppen.');await refreshGroups();}
  });
}
init();
