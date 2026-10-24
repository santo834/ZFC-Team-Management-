'use strict';

(() => {
  const STORAGE_KEY = 'zfc-portal-v1';
  const scriptUrl = document.currentScript?.src || new URL('assets/portal.js', location.href).href;
  const assetBase = new URL('.', scriptUrl);
  const GALLERY_IMAGE = new URL('art/hero.svg', assetBase).href;
  const CATEGORY_IMAGES = {
    insurance: new URL('art/insurance.svg', assetBase).href,
    sponsoring: new URL('art/sponsors.svg', assetBase).href,
    hq: new URL('art/hq.svg', assetBase).href,
    marketplace: new URL('art/marketplace.svg', assetBase).href
  };
  const teams = [
    {id:'summit-gp',name:'BWT Alpine F1 Team',mark:'A',logo:'alpine',color:'#0093cc',initialBalance:0},
    {id:'atlas-competition',name:'Aston Martin Aramco F1 Team',mark:'AM',logo:'aston-martin',color:'#00594f',initialBalance:0},
    {id:'cobalt-works',name:'Audi F1 Team',mark:'A',logo:'audi',color:'#d1001f',initialBalance:0},
    {id:'cadillac',name:'Cadillac F1 Team',mark:'C',color:'#c8a95b',initialBalance:0},
    {id:'scuderia-rosso',name:'Scuderia Ferrari HP',mark:'F',logo:'ferrari',color:'#dc0000',initialBalance:0},
    {id:'ironclad-racing',name:'TGR Haas F1 Team',mark:'H',logo:'haas',color:'#9da3a8',initialBalance:0},
    {id:'veloce-racing',name:'McLaren F1 Team',mark:'M',logo:'mclaren',color:'#ff8700',initialBalance:0},
    {id:'apex-motorsport',name:'Mercedes-AMG PETRONAS F1 Team',mark:'M',logo:'mercedes',color:'#00d2be',initialBalance:0},
    {id:'pulse-motorsport',name:'Visa Cash App Racing Bulls F1 Team',mark:'RB',logo:'racing-bulls',color:'#6692ff',initialBalance:0},
    {id:'northstar-gp',name:'Oracle Red Bull Racing',mark:'RBR',logo:'red-bull-racing',color:'#1e41ff',initialBalance:0},
    {id:'vector-racing',name:'Atlassian Williams F1 Team',mark:'W',logo:'williams',color:'#005aff',initialBalance:0}
  ];
  const teamLogo = team => new URL(`team-logos/${team.logo || team.id}.svg`, assetBase).href;
  const money = cents => new Intl.NumberFormat('de-DE',{style:'currency',currency:'EUR'}).format((Number(cents)||0)/100);
  const date = value => new Intl.DateTimeFormat('de-CH',{dateStyle:'medium'}).format(new Date(value));
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
  const uid = () => crypto.randomUUID();
  const $ = (selector, root=document) => root.querySelector(selector);
  const teamName = id => teams.find(team => team.id === id)?.name || 'Unbekanntes Team';
  const categoryName = (category='sponsoring') => ({insurance:'Insurance',sponsoring:'Sponsoring',hq:'HQ',marketplace:'Marketplace'})[category] || 'Marketplace';
  const CONTRACT_TYPES = [['driver','Fahrervertrag'],['team_principal','Teamchef-Vertrag'],['insurance','Insurance-Vertrag'],['sponsoring','Sponsoring-Vertrag'],['hq','HQ-Vertrag'],['driver_purchase','Fahrerkauf-Vertrag']];
  const contractTypeName = type => ({...Object.fromEntries(CONTRACT_TYPES),vehicle:'Fahrzeug-Vertrag'})[type] || type;
  const contractTypeOptions = (selected='') => CONTRACT_TYPES.map(([key,label])=>`<option value="${key}" ${key===selected?'selected':''}>${label}</option>`).join('');
  const emptyData = () => ({home:{title:'Herzlich willkommen',claim:'bei ZFC.',intro:'Entdecke Angebote und Möglichkeiten rund um unsere Teams. Wähle den Bereich, der dich interessiert.',image:GALLERY_IMAGE},teamLogos:{},offers:[],orders:[],invoices:[],contracts:[],bookings:[],tickets:[]});
  let data, currentTeamId, adminProfiles=[], adminTeamId=teams[0].id, statementMonth=new Date().toISOString().slice(0,7);

  function readImage(file) {
    const readAsDataUrl = blob => new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(blob);});
    if (file.size <= 1024*1024 || /svg|gif/.test(file.type)) return readAsDataUrl(file);
    return new Promise((resolve,reject)=>{
      const url = URL.createObjectURL(file), image = new Image();
      image.onload = () => {
        const scale = Math.min(1, 2000/Math.max(image.width,image.height));
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(image.width*scale); canvas.height = Math.round(image.height*scale);
        const context = canvas.getContext('2d');
        context.fillStyle = '#fff'; context.fillRect(0,0,canvas.width,canvas.height);
        context.drawImage(image,0,0,canvas.width,canvas.height);
        URL.revokeObjectURL(url);
        resolve(canvas.toDataURL('image/jpeg',0.88));
      };
      image.onerror = () => { URL.revokeObjectURL(url); readAsDataUrl(file).then(resolve,reject); };
      image.src = url;
    });
  }

  function load() {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (!stored) return emptyData();
    const parsed = JSON.parse(stored);
    if (!parsed || typeof parsed !== 'object' || !['home','teamLogos','offers','orders','invoices','contracts','bookings','tickets'].every(key => key in parsed) || !parsed.home || !Array.isArray(parsed.offers) || !Array.isArray(parsed.orders) || !Array.isArray(parsed.invoices) || !Array.isArray(parsed.contracts) || !Array.isArray(parsed.bookings) || !Array.isArray(parsed.tickets)) {
      throw new Error('Die lokalen Portal-Daten sind beschädigt. Bitte vor weiteren Änderungen ein Backup sichern.');
    }
    return parsed;
  }

  function save() {
    try {
      const shared = window.zfcSupabase ? {offers:[],orders:[],invoices:[],contracts:[],bookings:[],tickets:[]} : {};
      localStorage.setItem(STORAGE_KEY, JSON.stringify({...data,...shared}));
      return true;
    } catch (error) {
      showToast(`Speichern fehlgeschlagen: ${error.message}`, true);
      return false;
    }
  }

  function showToast(message, isError=false) {
    const toast = $('#portal-toast');
    if (!toast) return;
    toast.textContent = message;
    toast.hidden = false;
    toast.style.color = isError ? '#ffb1b1' : '';
    window.clearTimeout(showToast.timeout);
    showToast.timeout = window.setTimeout(() => { toast.hidden = true; }, 3600);
  }

  function balance(teamId) {
    const initial = teams.find(team=>team.id===teamId)?.initialBalance || 0;
    return initial + data.bookings.filter(entry => entry.teamId === teamId).reduce((total, entry) => total + (entry.direction === 'credit' ? entry.amount : -entry.amount), 0);
  }

  function teamOptions(selected='') {
    return teams.map(team => `<option value="${team.id}" ${team.id===selected?'selected':''}>${team.name}</option>`).join('');
  }

  function teamSelect(selected='') {
    return `<select name="teamId" required>${teamOptions(selected)}</select>`;
  }

  function statusBadge(status) {
    const labels = {open:'Offen',payment_requested:'Zahlung vorgemerkt',paid:'Bezahlt',pending:'In Prüfung',approved:'Freigegeben',signed:'Angenommen',declined:'Abgelehnt',in_progress:'In Bearbeitung',resolved:'Erledigt'};
    const color = ['paid','approved','signed','resolved'].includes(status) ? 'good' : ['open','payment_requested','pending','in_progress'].includes(status) ? 'pending' : '';
    return `<span class="portal-badge ${color}">${labels[status] || escapeHtml(status)}</span>`;
  }

  function layout(active, content, title='Admin Control Center') {
    const navigation = [
      ['overview','Übersicht'],['content','Startseite & Galaxy'],['offers','Angebote'],['orders','Kaufanfragen'],['ebanking','Team-E-Banking'],['finance','Teamkonten & Rechnungen'],['contracts','Verträge'],['accounts','Benutzer & Rollen'],['tickets','Probleme & Meldungen']
    ];
    return `<div class="portal-shell"><aside class="portal-sidebar">
      <a class="portal-brand" href="../index.html"><span class="portal-brand-mark">Z</span><span><strong>ZFC</strong><small>TEAM MANAGEMENT</small></span></a>
      <div class="portal-label">Arbeitsbereich</div><nav class="portal-nav" aria-label="Admin Navigation">${navigation.map(([key,label])=>`<button type="button" data-admin-tab="${key}" class="${active===key?'active':''}">${label}</button>`).join('')}</nav>
      <div class="portal-side-note">Admin Control Center<br><a href="../index.html">← Zur öffentlichen Website</a></div>
    </aside><main class="portal-main"><div class="portal-topbar"><div><strong>${escapeHtml(title)}</strong><br><small>Verwaltung · Saison 2026</small></div><div class="portal-actions">${window.zfcSupabase?'':'<span class="portal-badge pending">Lokale Demo</span>'}<button class="portal-button" type="button" data-sign-out>Abmelden</button></div></div>${content}</main><dialog class="portal-dialog" id="record-editor"></dialog><div id="portal-toast" class="portal-toast" role="status" hidden></div></div>`;
  }

  function editorControl(label, name, value, type='text', options=[]) {
    const safeValue = escapeHtml(value ?? '');
    if (type==='select') {
      return `<label>${label}<select name="${name}">${options.map(([option,labelText])=>`<option value="${escapeHtml(option)}" ${String(value)===option?'selected':''}>${escapeHtml(labelText)}</option>`).join('')}</select></label>`;
    }
    if (type==='textarea') return `<label class="full">${label}<textarea name="${name}">${safeValue}</textarea></label>`;
    return `<label>${label}<input name="${name}" type="${type}" value="${safeValue}"></label>`;
  }

  function openRecordEditor(type, id) {
    const collections = {offer:data.offers,order:data.orders,invoice:data.invoices,contract:data.contracts,booking:data.bookings,ticket:data.tickets};
    const item = collections[type]?.find(entry=>entry.id===id);
    const dialog = $('#record-editor');
    if (!item || !dialog) return;
    const fields = [];
    const team = (value=item.teamId) => editorControl('Team','teamId',value,'select',teams.map(entry=>[entry.id,entry.name]));
    const category = value => editorControl('Kategorie','category',value,'select',[['insurance','Insurance'],['sponsoring','Sponsoring'],['hq','HQ'],['marketplace','Marketplace']]);
    const status = (value, options) => editorControl('Status','status',value,'select',options);
    const amount = value => editorControl('Betrag in EUR','amount',(Number(value||0)/100).toFixed(2),'number');
    if (type==='offer') {
      fields.push(editorControl('Name','name',item.name),category(item.category),amount(item.amount),
        editorControl('Kurzbeschreibung','description',item.description,'textarea'),
        editorControl('Konditionen','terms',item.terms||'','textarea'),
        editorControl('Ziel-URL','url',item.url||'','url'),
        editorControl('Bild-URL (leer lassen, um das aktuelle Bild zu behalten)','image',item.image?.startsWith('data:')?'':(item.image||''),'url'),
        `<label class="full">Neues Bild hochladen (optional)<input name="imageFile" type="file" accept="image/*"></label>`,
        status(item.published===false?'unpublished':'published',[['published','Veröffentlicht'],['unpublished','Nicht veröffentlicht']]));
    } else if (type==='order') {
      fields.push(team(),editorControl('Angebot','offerName',item.offerName),category(item.category),amount(item.amount),
        editorControl('Kontakt','contactName',item.contactName),editorControl('E-Mail','email',item.email,'email'),
        editorControl('Unternehmen','company',item.company||''),editorControl('Rechnungsadresse','billingAddress',item.billingAddress||'','textarea'),
        editorControl('Kundenhinweise','notes',item.notes||'','textarea'),editorControl('Interne Admin-Notiz','adminNotes',item.adminNotes||'','textarea'),
        status(item.status,[['pending','Offen'],['approved','Freigegeben'],['declined','Abgelehnt'],['completed','Abgeschlossen']]));
    } else if (type==='invoice') {
      fields.push(team(),editorControl('Rechnungsnummer','number',item.number),amount(item.amount),
        editorControl('Beschreibung','description',item.description),editorControl('Fällig am','dueDate',item.dueDate,'date'),
        editorControl('Referenz','reference',item.reference||''),editorControl('Rechnung an','billToName',item.billToName||''),
        editorControl('Rechnungs-E-Mail (optional)','billToEmail',item.billToEmail||'','email'),
        editorControl('Unternehmen','billToCompany',item.billToCompany||''),
        editorControl('Rechnungsanschrift','billToAddress',item.billToAddress||'','textarea'),
        status(item.status,[['open','Offen'],['payment_requested','Zahlung vorgemerkt'],['void','Storniert'],...(item.status==='paid'?[['paid','Bezahlt']]:[])]));
    } else if (type==='contract') {
      fields.push(team(),editorControl('Vertragsart','type',item.type,'select',[...CONTRACT_TYPES,...(item.type==='vehicle'?[['vehicle','Fahrzeug-Vertrag']]:[])]),
        editorControl('Titel','title',item.title),editorControl('Konditionen','terms',item.terms,'textarea'),
        editorControl('Gültig bis','endDate',item.endDate,'date'),
        status(item.status,[['pending','Offen'],['signed','Angenommen'],['declined','Abgelehnt'],['terminated','Beendet']]));
    } else if (type==='booking') {
      fields.push(team(),editorControl('Art','direction',item.direction,'select',[['credit','Gutschrift'],['debit','Belastung']]),
        amount(item.amount),editorControl('Verwendungszweck','note',item.note));
    } else if (type==='ticket') {
      fields.push(team(),editorControl('Kategorie','category',item.category),editorControl('Titel','subject',item.subject),
        editorControl('Beschreibung','details',item.details,'textarea'),
        status(item.status,[['open','Offen'],['in_progress','In Bearbeitung'],['resolved','Erledigt']]));
    }
    dialog.innerHTML = `<form class="portal-form" data-form="record-edit" data-record-type="${type}" data-record-id="${escapeHtml(id)}"><h2 class="full">Eintrag bearbeiten</h2>${fields.join('')}<div class="portal-actions"><button class="portal-button primary">Änderungen speichern</button><button class="portal-button" type="button" data-close-editor>Abbrechen</button></div></form>`;
    dialog.showModal();
  }

  function statementFor(teamId, month) {
    const [year,mon] = month.split('-').map(Number);
    const start = new Date(year,mon-1,1), end = new Date(year,mon,1);
    const effect = entry => entry.direction==='credit' ? entry.amount : -entry.amount;
    const all = data.bookings.filter(entry=>entry.teamId===teamId);
    const opening = (teams.find(team=>team.id===teamId)?.initialBalance||0) + all.filter(entry=>new Date(entry.createdAt)<start).reduce((total,entry)=>total+effect(entry),0);
    const entries = all.filter(entry=>{const created=new Date(entry.createdAt);return created>=start && created<end;}).sort((a,b)=>new Date(a.createdAt)-new Date(b.createdAt));
    const income = entries.filter(entry=>entry.direction==='credit').reduce((total,entry)=>total+entry.amount,0);
    const expenses = entries.filter(entry=>entry.direction==='debit').reduce((total,entry)=>total+entry.amount,0);
    const invoices = data.invoices.filter(invoice=>invoice.teamId===teamId && new Date(invoice.createdAt)>=start && new Date(invoice.createdAt)<end);
    const openInvoices = data.invoices.filter(invoice=>invoice.teamId===teamId && ['open','payment_requested'].includes(invoice.status));
    return {start,end,opening,entries,income,expenses,closing:opening+income-expenses,invoices,openInvoices};
  }

  const monthLabel = month => new Intl.DateTimeFormat('de-CH',{month:'long',year:'numeric'}).format(new Date(`${month}-01T12:00:00`));

  function statementSection(teamId) {
    const summary = statementFor(teamId, statementMonth);
    return `<section class="portal-card" style="margin-top:15px" data-statement-section><h2>Monatsabrechnung</h2>
      <p class="portal-muted">Automatische Abrechnung aus allen Einnahmen (Gutschriften) und Ausgaben (Belastungen) des Teamkontos.</p>
      <div class="portal-actions" style="margin-bottom:12px"><label class="portal-label-text">Monat<input class="portal-select" type="month" data-statement-month value="${statementMonth}"></label><button class="portal-button primary" type="button" data-print-statement="${teamId}">Abrechnung als PDF</button></div>
      <div class="portal-grid"><article class="portal-card"><div class="portal-label-text">Anfangssaldo</div><div class="portal-stat">${money(summary.opening)}</div></article><article class="portal-card"><div class="portal-label-text">Einnahmen</div><div class="portal-stat">${money(summary.income)}</div></article><article class="portal-card"><div class="portal-label-text">Ausgaben</div><div class="portal-stat">${money(summary.expenses)}</div></article><article class="portal-card"><div class="portal-label-text">Endsaldo</div><div class="portal-stat">${money(summary.closing)}</div></article></div></section>`;
  }

  const DOC_STYLE = `@page{size:A4;margin:18mm 16mm}*{box-sizing:border-box}body{font:13px/1.55 'Helvetica Neue',Arial,sans-serif;color:#1c1f23;margin:0;padding:0}.sheet{max-width:780px;margin:0 auto;padding:34px 40px}.letterhead{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid #101418;padding-bottom:18px}.brand{display:flex;gap:12px;align-items:center}.brand-mark{width:44px;height:44px;border-radius:9px;background:#101418;color:#c7f36b;font-weight:800;font-size:24px;display:flex;align-items:center;justify-content:center}.brand strong{display:block;font-size:16px;letter-spacing:.04em}.brand small{color:#666;letter-spacing:.12em;font-size:10px}.doc-meta{text-align:right;font-size:12px;color:#444}.doc-meta b{color:#101418}h1{font-size:26px;margin:28px 0 4px;letter-spacing:-.01em}.subtitle{color:#666;margin:0 0 22px}h2{font-size:14px;margin:24px 0 6px;text-transform:uppercase;letter-spacing:.06em;color:#101418}.parties{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin:18px 0}.party{border:1px solid #d9dde2;border-radius:6px;padding:12px 14px}.party small{display:block;color:#777;text-transform:uppercase;letter-spacing:.08em;font-size:10px;margin-bottom:4px}table{width:100%;border-collapse:collapse;margin:10px 0}th{background:#101418;color:#fff;text-align:left;padding:8px 10px;font-size:11px;letter-spacing:.05em;text-transform:uppercase}td{padding:9px 10px;border-bottom:1px solid #e3e6ea;vertical-align:top}td.num,th.num{text-align:right;white-space:nowrap}tr.sum td{font-weight:700;border-top:2px solid #101418;background:#f4f6f8}.clause{margin:0 0 10px;text-align:justify}.terms{white-space:pre-wrap;border-left:3px solid #c7f36b;background:#f7f9f4;padding:10px 14px}.signatures{display:grid;grid-template-columns:1fr 1fr;gap:50px;margin-top:70px}.signatures div{border-top:1px solid #101418;padding-top:6px;font-size:12px;color:#444}.note{margin-top:30px;color:#777;font-size:11px;border-top:1px solid #e3e6ea;padding-top:10px}.footer{margin-top:30px;color:#777;font-size:10px;text-align:center;letter-spacing:.04em}.print-bar{position:sticky;top:0;background:#101418;padding:10px;text-align:center}.print-bar button{font:600 13px Arial;padding:8px 18px;border:0;border-radius:6px;background:#c7f36b;cursor:pointer}@media print{.print-bar{display:none}.sheet{padding:0}}`;

  function openDocument(title, number, bodyHtml, dateText=date(new Date())) {
    const printWindow = window.open('', '_blank', 'width=900,height=1000');
    if (!printWindow) { showToast('Druckfenster blockiert. Bitte Pop-ups für diese Seite erlauben.',true); return; }
    printWindow.document.write(`<!doctype html><html lang="de"><head><meta charset="utf-8"><title>${escapeHtml(title)} ${escapeHtml(number)}</title><style>${DOC_STYLE}</style></head><body><div class="print-bar"><button onclick="window.print()">Als PDF speichern / Drucken</button></div><div class="sheet"><div class="letterhead"><div class="brand"><span class="brand-mark">Z</span><span><strong>ZFC · Zenith Formula Championship</strong><small>TEAM MANAGEMENT · SAISON 2026</small></span></div><div class="doc-meta"><b>${escapeHtml(title)}</b><br>Nr. ${escapeHtml(number)}<br>${escapeHtml(dateText)}</div></div>${bodyHtml}<div class="footer">ZFC · Zenith Formula Championship · Dieses Dokument wurde digital erstellt.</div></div></body></html>`);
    printWindow.document.close();
  }

  const CONTRACT_CLAUSES = {
    driver:['Die ZFC verpflichtet das Team, den vereinbarten Fahrer in der Saison 2026 einzusetzen; der Fahrer vertritt das Team bei allen Rennveranstaltungen der Meisterschaft.','Der Fahrer verpflichtet sich zur Einhaltung des Sportlichen Reglements, der Teamanweisungen sowie zu professionellem Verhalten gegenüber Team, Partnern und Öffentlichkeit.','Vergütung, Prämien und Nebenleistungen richten sich nach den unten genannten Konditionen.'],
    team_principal:['Der Teamchef leitet das Team operativ und sportlich und vertritt es gegenüber der ZFC, den Fahrern und Partnern.','Er ist für die Einhaltung des Reglements, die ordnungsgemäße Führung des Teamkontos und die Meldung relevanter Vorkommnisse verantwortlich.','Vergütung und besondere Befugnisse richten sich nach den unten genannten Konditionen.'],
    insurance:['Die ZFC vermittelt den Versicherungsschutz im unten beschriebenen Umfang für das Team, seine Fahrer und sein Material.','Das Team ist verpflichtet, versicherungsrelevante Ereignisse unverzüglich zu melden und die Prämien fristgerecht zu begleichen.','Leistungsumfang, Selbstbehalt und Prämien richten sich nach den unten genannten Konditionen.'],
    sponsoring:['Der Sponsor erhält die vereinbarten Werbe- und Präsentationsrechte beim Team im Rahmen der Saison 2026.','Das Team stellt die vereinbarten Leistungen bereit; der Sponsor entrichtet die vereinbarte Sponsoringsumme fristgerecht.','Umfang der Rechte, Zahlungsplan und Laufzeit richten sich nach den unten genannten Konditionen.'],
    hq:['Die ZFC überlässt dem Team die unten beschriebenen Hauptquartier-Leistungen (Nutzung, Ausbau oder Services) für die Vertragslaufzeit.','Das Team nutzt die Leistungen bestimmungsgemäß und trägt anfallende Entgelte gemäß Konditionen.','Umfang, Entgelt und Nutzungsbedingungen richten sich nach den unten genannten Konditionen.'],
    driver_purchase:['Das Team erwirbt die vertraglichen Rechte an dem unten genannten Fahrer zu den vereinbarten Bedingungen.','Der Kaufpreis wird über das Teamkonto abgewickelt; der Rechteübergang erfolgt nach vollständiger Zahlung.','Kaufpreis, Zahlungsplan und Übergabezeitpunkt richten sich nach den unten genannten Konditionen.'],
    vehicle:['Gegenstand dieses Vertrags ist das unten beschriebene Fahrzeug.','Die Parteien verpflichten sich zur Erfüllung der vereinbarten Leistungen.','Details richten sich nach den unten genannten Konditionen.']
  };

  function contractNumber(contract) { return `VT-${new Date(contract.createdAt||Date.now()).getFullYear()}-${String(contract.id).replace(/-/g,'').slice(0,6).toUpperCase()}`; }

  function contractPrint(contract) {
    const team = teams.find(entry=>entry.id===contract.teamId);
    const clauses = (CONTRACT_CLAUSES[contract.type]||CONTRACT_CLAUSES.vehicle).map((text,index)=>`<h2>§ ${index+2}</h2><p class="clause">${escapeHtml(text)}</p>`).join('');
    const statusText = {pending:'Zur Prüfung',signed:'Angenommen',declined:'Abgelehnt',terminated:'Beendet'}[contract.status] || contract.status;
    openDocument(contractTypeName(contract.type), contractNumber(contract), `<h1>${escapeHtml(contract.title)}</h1><p class="subtitle">${escapeHtml(contractTypeName(contract.type))} · Status: ${escapeHtml(statusText)}</p>
      <div class="parties"><div class="party"><small>Vertragspartei A</small><strong>ZFC · Zenith Formula Championship</strong><br>vertreten durch die Verwaltung</div><div class="party"><small>Vertragspartei B</small><strong>${escapeHtml(team?.name||'Team')}</strong><br>vertreten durch die Teamleitung</div></div>
      <h2>§ 1 Vertragsgegenstand</h2><p class="clause">Dieser ${escapeHtml(contractTypeName(contract.type))} regelt die Rechte und Pflichten der Parteien in der Saison 2026 und gilt bis zum ${escapeHtml(date(contract.endDate))}.</p>${clauses}
      <h2>Individuelle Konditionen</h2><div class="terms">${escapeHtml(contract.terms)}</div>
      <h2>§ 5 Laufzeit und Schlussbestimmungen</h2><p class="clause">Der Vertrag endet am ${escapeHtml(date(contract.endDate))}, sofern er nicht vorzeitig einvernehmlich beendet wird. Änderungen bedürfen der Textform. Sollte eine Bestimmung unwirksam sein, bleibt der Vertrag im Übrigen wirksam.</p>
      <div class="signatures"><div>Ort, Datum · ZFC Verwaltung</div><div>Ort, Datum · ${escapeHtml(team?.name||'Team')}</div></div>
      <p class="note">Vertragsentwurf. Die Annahme im Portal ersetzt keine rechtsgültige Unterschrift; vor Verwendung rechtlich prüfen lassen.</p>`, date(contract.createdAt||new Date()));
  }

  function statementPrint(teamId, month) {
    const team = teams.find(entry=>entry.id===teamId);
    const summary = statementFor(teamId, month);
    const rows = summary.entries.map(entry=>`<tr><td>${date(entry.createdAt)}</td><td>${escapeHtml(entry.note)}</td><td class="num">${entry.direction==='credit'?money(entry.amount):''}</td><td class="num">${entry.direction==='debit'?money(entry.amount):''}</td></tr>`).join('') || '<tr><td colspan="4">Keine Buchungen in diesem Monat.</td></tr>';
    const openRows = summary.openInvoices.map(invoice=>`<tr><td>${escapeHtml(invoice.number)}</td><td>${escapeHtml(invoice.description)}</td><td>${date(invoice.dueDate)}</td><td class="num">${money(invoice.amount)}</td></tr>`).join('') || '<tr><td colspan="4">Keine offenen Rechnungen.</td></tr>';
    openDocument('Monatsabrechnung', `MA-${month}-${teamId.slice(0,4).toUpperCase()}`, `<h1>Monatsabrechnung ${escapeHtml(monthLabel(month))}</h1><p class="subtitle">${escapeHtml(team.name)}</p>
      <div class="parties"><div class="party"><small>Konto</small><strong>${escapeHtml(team.name)}</strong><br>Teamkonto · EUR</div><div class="party"><small>Zeitraum</small><strong>${date(summary.start)} – ${date(new Date(summary.end-86400000))}</strong></div></div>
      <h2>Zusammenfassung</h2><table><tr><td>Anfangssaldo</td><td class="num">${money(summary.opening)}</td></tr><tr><td>Einnahmen (Gutschriften)</td><td class="num">${money(summary.income)}</td></tr><tr><td>Ausgaben (Belastungen)</td><td class="num">− ${money(summary.expenses)}</td></tr><tr class="sum"><td>Endsaldo</td><td class="num">${money(summary.closing)}</td></tr></table>
      <h2>Buchungen</h2><table><thead><tr><th>Datum</th><th>Verwendungszweck</th><th class="num">Einnahme</th><th class="num">Ausgabe</th></tr></thead><tbody>${rows}<tr class="sum"><td colspan="2">Summe</td><td class="num">${money(summary.income)}</td><td class="num">${money(summary.expenses)}</td></tr></tbody></table>
      <h2>Offene Rechnungen</h2><table><thead><tr><th>Nummer</th><th>Beschreibung</th><th>Fällig</th><th class="num">Betrag</th></tr></thead><tbody>${openRows}</tbody></table>
      <p class="note">Automatisch erstellt aus den Kontobuchungen des Teamkontos. Tatsächliche Überweisungen erfolgen außerhalb des Portals.</p>`);
  }

  function heading(kicker,title,description='') {
    return `<div class="portal-heading"><div><div class="portal-kicker">${kicker}</div><h1>${title}</h1>${description?`<div class="portal-muted">${description}</div>`:''}</div></div>`;
  }

  function renderAdminTab(tab='overview') {
    const root = $('#portal-root');
    if (!root) return;
    let content = '';
    if (tab==='overview') {
      const openOrders = data.orders.filter(order=>order.status==='pending').length;
      const pendingInvoices = data.invoices.filter(invoice=>invoice.status!=='paid').length;
      content = `${heading('Control Center','Guten Tag, Admin.','Alle wichtigen Vorgänge und Teamkonten an einem Ort.')}
        <div class="portal-grid">
          <article class="portal-card"><div class="portal-label-text">Teams im Grid</div><div class="portal-stat">${teams.length}</div><div class="portal-label-text">Teamkonten verwalten</div></article>
          <article class="portal-card"><div class="portal-label-text">Offene Sponsoren-Akten</div><div class="portal-stat">${openOrders}</div><div class="portal-label-text">Neue Kaufanfragen</div></article>
          <article class="portal-card"><div class="portal-label-text">Offene Rechnungen</div><div class="portal-stat">${pendingInvoices}</div><div class="portal-label-text">Teamkonto-Vorgänge</div></article>
          <article class="portal-card"><div class="portal-label-text">Verträge</div><div class="portal-stat">${data.contracts.length}</div><div class="portal-label-text">Angebote und Annahmen</div></article>
        </div>
        <div class="portal-grid two" style="margin-top:15px">
          <section class="portal-card"><h2>Zuletzt eingegangen</h2>${data.orders.length?`<div class="portal-item-list">${data.orders.slice().reverse().slice(0,4).map(order=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(order.offerName)}</strong><small>${escapeHtml(teamName(order.teamId))} · ${escapeHtml(order.contactName)}</small></div>${statusBadge(order.status)}</div>`).join('')}</div>`:'<div class="portal-empty">Noch keine Sponsoren-Anfragen.</div>'}</section>
          <section class="portal-card"><h2>Schnellzugriff</h2><div class="portal-actions"><button class="portal-button primary" data-admin-tab="offers">Angebot erstellen</button><button class="portal-button" data-admin-tab="finance">Rechnung erstellen</button><button class="portal-button" data-admin-tab="contracts">Vertrag anlegen</button></div><p>Änderungen werden in diesem Browser gespeichert.</p></section>
        </div>
        ${window.zfcSupabase?'':'<div class="portal-warning">Demo-Modus: Benutzerkonten und Änderungen werden nicht zentral gespeichert. Bitte keine echten Passwörter, Bank- oder Vertragsdaten eingeben.</div>'}`;
    } else if (tab==='content') {
      content = `${heading('Website bearbeiten','Startseite & Bildgalerie','Die Texte und das Titelbild werden auf der öffentlichen Startseite aktualisiert – auf diesem Browser.')}
        <section class="portal-card"><form class="portal-form" data-form="home">
          <label>Titel der Startseite<input name="title" maxlength="70" required value="${escapeHtml(data.home.title)}"></label>
          <label>Claim / zweite Titelzeile<input name="claim" maxlength="70" required value="${escapeHtml(data.home.claim)}"></label>
          <label class="full">Einleitungstext<textarea name="intro" maxlength="300" required>${escapeHtml(data.home.intro)}</textarea></label>
          <label class="full">Bild aus der Galerie<select name="gallery">${data.home.image!==GALLERY_IMAGE?`<option value="${escapeHtml(data.home.image)}" selected>Aktuelles Bild</option>`:''}<option value="${GALLERY_IMAGE}" ${data.home.image===GALLERY_IMAGE?'selected':''}>Rennsport-Motiv · Website-Galerie</option><option value="upload">Eigenes Bild vom Gerät auswählen …</option></select></label>
          <label class="full">Eigenes Bild (optional)<input name="imageFile" type="file" accept="image/*"><small class="portal-muted">Beliebige Bilddatei aus der Gerätegalerie; große Bilder werden automatisch optimiert.</small></label>
          <img class="portal-gallery-preview" data-home-preview src="${escapeHtml(data.home.image || GALLERY_IMAGE)}" alt="Vorschau des Startseitenbilds">
          <div class="portal-actions"><button class="portal-button primary">Startseite speichern</button></div>
        </form></section>
        <section class="portal-card" style="margin-top:15px"><h2>Teamlogos im E-Banking</h2><form class="portal-form" data-form="team-logo">
          <label>Team${teamSelect()}</label>
          <label>Eigenes Logo (optional)<input name="imageFile" type="file" accept="image/*"><small class="portal-muted">Beliebige Bilddatei. Ohne Upload wird das gestaltete Team-Badge verwendet.</small></label>
          <div class="portal-actions"><button class="portal-button">Teamlogo speichern</button></div>
        </form></section>`;
    } else if (tab==='offers') {
      content = `${heading('Sponsorenshop','Angebote verwalten','Angebote erstellen, veröffentlichen und zentral bearbeiten.')}
        <div class="portal-grid two">
          <section class="portal-card"><h2>Neues Angebot</h2><form class="portal-form" data-form="offer">
              <label>Name<input name="name" maxlength="80" required></label>
              <label>Kategorie<select name="category"><option value="insurance">Insurance</option><option value="sponsoring">Sponsoring</option><option value="hq">HQ</option><option value="marketplace">Marketplace</option></select></label>
            <label>Preis in EUR<input name="amount" type="number" min="0.01" step="0.01" required></label>
            <label class="full">Kurzbeschreibung<textarea name="description" maxlength="300" required></textarea></label>
            <label class="full">Konditionen<textarea name="terms" maxlength="2000" required></textarea></label>
            <label class="full">Ziel-URL (optional)<input name="url" type="url" placeholder="https://…"></label>
            <label class="full">Bild aus der Galerie<select name="gallery"><option value="${GALLERY_IMAGE}">Rennsport-Motiv · Website-Galerie</option><option value="upload">Eigenes Bild vom Gerät auswählen …</option></select></label>
            <label class="full">Eigenes Bild (optional)<input name="imageFile" type="file" accept="image/*"><small class="portal-muted">Beliebige Bilddatei aus der Gerätegalerie; große Bilder werden automatisch optimiert.</small></label>
            <div class="portal-actions"><button class="portal-button primary">Angebot veröffentlichen</button></div>
          </form></section>
          <section class="portal-card"><h2>Angebote</h2>${data.offers.length?`<div class="portal-item-list">${data.offers.map(offer=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(offer.name)}</strong><small>${categoryName(offer.category)} · ${money(offer.amount)} · ${escapeHtml(offer.description)}</small><small>${escapeHtml(offer.terms||'')} · ${offer.published===false?'Nicht veröffentlicht':'Veröffentlicht'}</small></div><div class="portal-actions"><button class="portal-button" data-edit-record="offer" data-record-id="${offer.id}">Bearbeiten</button><button class="portal-button danger" data-delete-offer="${offer.id}">Entfernen</button></div></div>`).join('')}</div>`:'<div class="portal-empty">Noch keine Angebote angelegt.</div>'}</section>
        </div>`;
    } else if (tab==='orders') {
      content = `${heading('Eingang','Sponsoren-Akten','Kaufanfragen aus dem Sponsorenbereich prüfen und weiterbearbeiten.')}
        <section class="portal-card"><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Angebot / Kontakt</th><th>Team</th><th>Datum</th><th>Status</th><th>Aktion</th></tr></thead><tbody>
        ${data.orders.length?data.orders.slice().reverse().map(order=>`<tr><td><strong>${escapeHtml(order.offerName)}</strong><br><span class="portal-muted">${categoryName(order.category)} · ${escapeHtml(order.contactName)} · ${escapeHtml(order.email)}</span><br>${escapeHtml(order.company||'')} ${money(order.amount)}<br>${escapeHtml(order.billingAddress||'')}<br><span class="portal-muted">Konditionen: ${escapeHtml(order.terms||'')}<br>${escapeHtml(order.notes||'')}<br>${escapeHtml(order.adminNotes||'')}</span></td><td>${escapeHtml(teamName(order.teamId))}</td><td>${date(order.createdAt)}</td><td>${statusBadge(order.status)}</td><td><div class="portal-actions"><button class="portal-button" data-edit-record="order" data-record-id="${order.id}">Bearbeiten</button>${order.status==='pending'?`<button class="portal-button primary" data-approve-order="${order.id}">Prüfen & Rechnung</button>`:''}</div></td></tr>`).join(''):'<tr><td colspan="5" class="portal-empty">Noch keine Anfragen vorhanden.</td></tr>'}
        </tbody></table></div></section>`;
    } else if (tab==='finance') {
      content = `${heading('Teamkonten','Rechnungen & Buchungen','Rechnungen hier erstellen; Teamchefs sehen sie im Teamkonto.')}
        <div class="portal-grid two"><section class="portal-card"><h2>Rechnung erstellen</h2><form class="portal-form" data-form="invoice">
          <label>Team${teamSelect()}</label><label>Betrag in EUR<input name="amount" type="number" min="0.01" step="0.01" required></label>
          <label class="full">Beschreibung<input name="description" maxlength="120" required></label>
          <label>Rechnung an<input name="billToName" maxlength="120"></label><label>Rechnungs-E-Mail (optional)<input name="billToEmail" type="email" maxlength="254" placeholder="optional"></label>
          <label>Unternehmen<input name="billToCompany" maxlength="120"></label><label class="full">Rechnungsanschrift<textarea name="billToAddress" maxlength="300"></textarea></label>
          <label>Fällig am<input name="dueDate" type="date" required></label>
          <label>Referenz / Aktennummer<input name="reference" maxlength="40" placeholder="Optional"></label>
          <div class="portal-actions"><button class="portal-button primary">Rechnung erstellen</button></div>
        </form></section><section class="portal-card"><h2>Manuelle Buchung</h2><form class="portal-form" data-form="booking">
          <label>Team${teamSelect()}</label><label>Art<select name="direction"><option value="credit">Gutschrift</option><option value="debit">Belastung</option></select></label>
          <label>Betrag in EUR<input name="amount" type="number" min="0.01" step="0.01" required></label>
          <label>Verwendungszweck<input name="note" maxlength="120" required></label>
          <div class="portal-actions"><button class="portal-button">Buchung erfassen</button></div>
        </form></section></div>
        <section class="portal-card" style="margin-top:15px"><h2>Rechnungsjournal</h2><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Rechnung</th><th>Team</th><th>Fällig</th><th>Betrag</th><th>Status</th><th>Aktion</th></tr></thead><tbody>${data.invoices.length?data.invoices.slice().reverse().map(invoice=>`<tr><td>${escapeHtml(invoice.number)}<br>${escapeHtml(invoice.description)}</td><td>${escapeHtml(teamName(invoice.teamId))}</td><td>${date(invoice.dueDate)}</td><td>${money(invoice.amount)}</td><td>${statusBadge(invoice.status)}</td><td><div class="portal-actions"><button class="portal-button" data-edit-record="invoice" data-record-id="${invoice.id}">Bearbeiten</button><button class="portal-button" data-print-invoice="${invoice.id}">PDF</button>${invoice.status==='payment_requested'?`<button class="portal-button primary" data-confirm-payment="${invoice.id}">Zahlung bestätigen</button>`:''}</div></td></tr>`).join(''):'<tr><td colspan="6" class="portal-empty">Noch keine Rechnungen.</td></tr>'}</tbody></table></div></section>
        <section class="portal-card" style="margin-top:15px"><h2>Teamkonten & Startkapital</h2><div class="portal-grid">${teams.map(team=>`<article class="portal-card" data-initial-capital-team="${team.id}"><div class="portal-item"><img class="portal-team-mark" style="object-fit:contain;background:transparent" src="${teamLogo(team)}" alt="${escapeHtml(team.name)}-Logo"><strong>${escapeHtml(team.name)}</strong></div><div class="portal-stat">${money(balance(team.id))}</div><label class="portal-label-text">Startkapital in EUR<input class="portal-select" data-initial-capital type="number" min="0" step="0.01" value="${(team.initialBalance/100).toFixed(2)}"></label><button class="portal-button" type="button" data-save-initial-capital="${team.id}">Startkapital speichern</button><a class="portal-button" href="../team/index.html?team=${team.id}">Team-E-Banking öffnen ↗</a></article>`).join('')}</div></section>
        <section class="portal-card" style="margin-top:15px"><h2>Kontobuchungen</h2><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Team</th><th>Datum</th><th>Verwendungszweck</th><th>Betrag</th><th>Aktion</th></tr></thead><tbody>${data.bookings.length?data.bookings.map(entry=>`<tr><td>${escapeHtml(teamName(entry.teamId))}</td><td>${date(entry.createdAt)}</td><td>${escapeHtml(entry.note)}</td><td>${entry.direction==='credit'?'+':'−'} ${money(entry.amount)}</td><td><button class="portal-button" data-edit-record="booking" data-record-id="${entry.id}">Bearbeiten</button></td></tr>`).join(''):'<tr><td colspan="5" class="portal-empty">Noch keine Buchungen.</td></tr>'}</tbody></table></div></section>`;
    } else if (tab==='contracts') {
      content = `${heading('Dokumentenverwaltung','Verträge','Vertragsentwürfe für Sponsoring, Versicherung, HQ und Fahrzeuge dem Team zur Prüfung vorlegen.')}
        <div class="portal-grid two"><section class="portal-card"><h2>Vertragsentwurf anlegen</h2><form class="portal-form" data-form="contract" data-return-tab="contracts">
          <label>Team${teamSelect(adminTeamId)}</label><label>Vertragsart<select name="type">${contractTypeOptions()}</select></label>
          <label class="full">Titel<input name="title" maxlength="100" required></label>
          <label class="full">Konditionen / Zusammenfassung<textarea name="terms" maxlength="1500" required></textarea></label>
          <label>Gültig bis<input name="endDate" type="date" required></label><div class="portal-actions"><button class="portal-button primary">Zur Prüfung senden</button></div>
        </form></section><section class="portal-card"><h2>Hinweis</h2><p>Die Annahme im Demo-Portal ist keine rechtsverbindliche elektronische Signatur. Vor echten Vereinbarungen sind Backend, Identitätsprüfung und rechtliche Dokumente erforderlich.</p></section></div>
        <section class="portal-card" style="margin-top:15px"><h2>Vertragsübersicht</h2><div class="portal-item-list">${data.contracts.length?data.contracts.slice().reverse().map(contract=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(contract.title)}</strong><small>${escapeHtml(contractTypeName(contract.type))} · ${escapeHtml(teamName(contract.teamId))} · gültig bis ${date(contract.endDate)}</small></div><div class="portal-actions">${statusBadge(contract.status)}<button class="portal-button" data-print-contract="${contract.id}">PDF</button><button class="portal-button" data-edit-record="contract" data-record-id="${contract.id}">Bearbeiten</button></div></div>`).join(''):'<div class="portal-empty">Noch keine Verträge erfasst.</div>'}</div></section>`;
    } else if (tab==='ebanking') {
      const team = teams.find(entry=>entry.id===adminTeamId) || teams[0];
      const teamContracts = data.contracts.filter(contract=>contract.teamId===team.id);
      const teamInvoices = data.invoices.filter(invoice=>invoice.teamId===team.id);
      content = `${heading('Team-E-Banking','Teamkonto verwalten','Verträge, Monatsabrechnung und Rechnungen des ausgewählten Teams an einem Ort.')}
        <section class="portal-card"><label class="portal-label-text">Team auswählen<select class="portal-select" data-ebank-team>${teamOptions(team.id)}</select></label>
          <div class="portal-grid" style="margin-top:15px"><article class="portal-card"><div class="portal-item"><img class="portal-team-mark" style="object-fit:contain;background:transparent" src="${escapeHtml(data.teamLogos[team.id]||teamLogo(team))}" alt=""><strong>${escapeHtml(team.name)}</strong></div></article>
          <article class="portal-card"><div class="portal-label-text">Kontostand</div><div class="portal-stat">${money(balance(team.id))}</div></article>
          <article class="portal-card"><div class="portal-label-text">Offene Rechnungen</div><div class="portal-stat">${teamInvoices.filter(invoice=>!['paid','void'].includes(invoice.status)).length}</div></article>
          <article class="portal-card"><div class="portal-label-text">Verträge</div><div class="portal-stat">${teamContracts.length}</div></article></div></section>
        <div class="portal-grid two" style="margin-top:15px"><section class="portal-card"><h2>Vertrag für ${escapeHtml(team.name)} anlegen</h2><form class="portal-form" data-form="contract" data-return-tab="ebanking">
          <input type="hidden" name="teamId" value="${team.id}">
          <label>Vertragsart<select name="type">${contractTypeOptions()}</select></label><label>Gültig bis<input name="endDate" type="date" required></label>
          <label class="full">Titel<input name="title" maxlength="100" required></label>
          <label class="full">Konditionen / Zusammenfassung<textarea name="terms" maxlength="1500" required></textarea></label>
          <div class="portal-actions"><button class="portal-button primary">Vertrag anlegen</button></div></form></section>
        <section class="portal-card"><h2>Verträge</h2><div class="portal-item-list">${teamContracts.length?teamContracts.slice().reverse().map(contract=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(contract.title)}</strong><small>${escapeHtml(contractTypeName(contract.type))} · gültig bis ${date(contract.endDate)}</small></div><div class="portal-actions">${statusBadge(contract.status)}<button class="portal-button" data-print-contract="${contract.id}">PDF</button><button class="portal-button" data-edit-record="contract" data-record-id="${contract.id}">Bearbeiten</button></div></div>`).join(''):'<div class="portal-empty">Noch keine Verträge für dieses Team.</div>'}</div></section></div>
        ${statementSection(team.id)}
        <section class="portal-card" style="margin-top:15px"><h2>Rechnungen</h2><div class="portal-item-list">${teamInvoices.length?teamInvoices.slice().reverse().map(invoice=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(invoice.number)} · ${escapeHtml(invoice.description)}</strong><small>${money(invoice.amount)} · fällig ${date(invoice.dueDate)}</small></div><div class="portal-actions">${statusBadge(invoice.status)}<button class="portal-button" data-print-invoice="${invoice.id}">PDF</button>${invoice.status==='payment_requested'?`<button class="portal-button primary" data-confirm-payment="${invoice.id}">Zahlung bestätigen</button>`:''}</div></div>`).join(''):'<div class="portal-empty">Keine Rechnungen vorhanden.</div>'}</div></section>`;
    } else if (tab==='accounts') {
      content = `${heading('Zugriffsverwaltung','Benutzer & Rollen','Lege Konten unter Supabase Auth an und weise ihnen hier die Rolle und bei Teamchefs das Team zu.')}
        <section class="portal-card"><div class="portal-actions" style="margin-bottom:12px"><button class="portal-button" type="button" data-refresh-profiles>Profile aktualisieren</button></div><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Benutzer</th><th>Rolle</th><th>Team</th><th></th></tr></thead><tbody>
          ${adminProfiles.length?adminProfiles.map(profile=>`<tr data-profile-row="${escapeHtml(profile.id)}"><td><strong>${escapeHtml(profile.display_name)}</strong><br><span class="portal-muted">${escapeHtml(profile.email||'Keine E-Mail im Profil')}</span></td><td><select class="portal-select" data-user-role><option value="team_chief" ${profile.role==='team_chief'?'selected':''}>Teamchef</option><option value="admin" ${profile.role==='admin'?'selected':''}>Admin</option></select></td><td><select class="portal-select" data-user-team ${profile.role==='admin'?'disabled':''}>${teamOptions(profile.team_id||'')}</select></td><td><button class="portal-button primary" data-save-profile-role="${escapeHtml(profile.id)}">Speichern</button></td></tr>`).join(''):'<tr><td colspan="4" class="portal-empty">Noch keine Profile vorhanden. Lege Benutzer zuerst unter Supabase → Authentication → Users an.</td></tr>'}
        </tbody></table></div></section>
        <div class="portal-warning">Neue E-Mail-/Passwort-Konten erstellst du im Supabase Dashboard unter Authentication → Users. Nach der E-Mail-Bestätigung erscheint das Profil hier zur Rollenzuweisung.</div>`;
    } else {
      content = `${heading('Support & Betrieb','Probleme und Meldungen','Alle eingereichten Team-Anliegen zentral ansehen und ihren Bearbeitungsstand aktualisieren.')}
        <section class="portal-card"><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Meldung</th><th>Team</th><th>Erstellt</th><th>Status</th><th>Aktion</th></tr></thead><tbody>
        ${data.tickets.length?data.tickets.slice().reverse().map(ticket=>`<tr><td><strong>${escapeHtml(ticket.subject)}</strong><br><span class="portal-muted">${escapeHtml(ticket.category)} · ${escapeHtml(ticket.details)}</span></td><td>${escapeHtml(teamName(ticket.teamId))}</td><td>${date(ticket.createdAt)}</td><td>${statusBadge(ticket.status)}</td><td><div class="portal-actions"><button class="portal-button" data-edit-record="ticket" data-record-id="${ticket.id}">Bearbeiten</button>${ticket.status!=='in_progress'?`<button class="portal-button" data-ticket-status="${ticket.id}" data-next-status="in_progress">In Bearbeitung</button>`:''}${ticket.status!=='resolved'?`<button class="portal-button primary" data-ticket-status="${ticket.id}" data-next-status="resolved">Erledigen</button>`:''}</div></td></tr>`).join(''):'<tr><td colspan="5" class="portal-empty">Keine offenen Meldungen vorhanden.</td></tr>'}
        </tbody></table></div></section>`;
    }
    root.innerHTML = layout(tab,content);
  }

  function renderTeam(teamId) {
    const root = $('#portal-root');
    if (!root) return;
    const selected = teams.find(team=>team.id===(window.zfcProfile?.role==='team_chief'?window.zfcProfile.team_id:teamId)) || teams[0];
    currentTeamId = selected.id;
    const invoices = data.invoices.filter(invoice=>invoice.teamId===selected.id);
    const contracts = data.contracts.filter(contract=>contract.teamId===selected.id);
    const bookings = data.bookings.filter(entry=>entry.teamId===selected.id).slice().reverse();
    const tickets = data.tickets.filter(ticket=>ticket.teamId===selected.id);
    root.innerHTML = `<div class="portal-shell"><aside class="portal-sidebar">
      <a class="portal-brand" href="../index.html"><span class="portal-team-mark" style="--team-color:${selected.color}">${selected.mark}</span><span><strong>${escapeHtml(selected.name)}</strong><small>TEAMKONTO · SAISON 2026</small></span></a>
      <div class="portal-label">Team Workspace</div><nav class="portal-nav"><a href="#konto">Kontenübersicht</a><a href="#rechnungen">Rechnungen</a><a href="#vertraege">Verträge</a><a href="#meldungen">Probleme melden</a><a href="../sponsors/shop.html">Sponsoren-Shop</a></nav>
      <div class="portal-side-note"><a href="../index.html">← Zur öffentlichen Website</a><br><button class="portal-button" type="button" data-sign-out>Abmelden</button></div>
    </aside><main class="portal-main"><div class="portal-topbar"><div><strong>Team-E-Banking</strong><br><small>Willkommen im digitalen Teamkonto</small></div><div class="portal-actions">${window.zfcSupabase?'<button class="portal-button" type="button" data-sign-out>Abmelden</button>':`<label class="portal-label-text">Demo-Team auswählen <select class="portal-select" data-team-picker aria-label="Demo-Team auswählen">${teamOptions(selected.id)}</select></label>`}</div></div>
      <section id="konto">${heading('Teamkonto','Finanzübersicht',`Team-Logo und Kontobewegungen für ${escapeHtml(selected.name)}.`)}
        <div class="portal-grid"><article class="portal-card portal-balance"><div class="portal-label-text">Verfügbarer Kontostand</div><div class="portal-stat">${money(balance(selected.id))}</div><div class="portal-label-text">Demo-Buchungen in EUR</div></article><article class="portal-card"><div class="portal-label-text">Offene Rechnungen</div><div class="portal-stat">${invoices.filter(invoice=>invoice.status!=='paid').length}</div><div class="portal-label-text">Fällig oder in Bearbeitung</div></article><article class="portal-card"><div class="portal-label-text">Verträge</div><div class="portal-stat">${contracts.length}</div><div class="portal-label-text">Entwürfe und Vereinbarungen</div></article><article class="portal-card"><div class="portal-label-text">Team-Logo</div><div class="portal-item"><img class="portal-team-mark" style="object-fit:contain;background:transparent" src="${escapeHtml(data.teamLogos[selected.id]||teamLogo(selected))}" alt="${escapeHtml(selected.name)}-Logo"><strong>${escapeHtml(selected.name)}</strong></div><div class="portal-label-text">${data.teamLogos[selected.id]?'Individuelles Logo':'Eigenständiges Team-Badge'}</div></article></div>
        <div class="portal-grid two" style="margin-top:15px"><section class="portal-card" id="rechnungen"><h2>Rechnungen</h2><div class="portal-item-list">${invoices.length?invoices.slice().reverse().map(invoice=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(invoice.number)} · ${escapeHtml(invoice.description)}</strong><small>${money(invoice.amount)} · fällig ${date(invoice.dueDate)}</small></div><div class="portal-actions">${statusBadge(invoice.status)}<button class="portal-button" data-print-invoice="${invoice.id}">PDF / Drucken</button>${invoice.status==='open'?`<button class="portal-button primary" data-request-payment="${invoice.id}">Zahlung vormerken</button>`:''}</div></div>`).join(''):'<div class="portal-empty">Keine Rechnungen vorhanden.</div>'}</div></section>
        <section class="portal-card" id="vertraege"><h2>Verträge</h2><div class="portal-item-list">${contracts.length?contracts.slice().reverse().map(contract=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(contract.title)}</strong><small>${escapeHtml(contractTypeName(contract.type))} · gültig bis ${date(contract.endDate)}<br>${escapeHtml(contract.terms)}</small></div><div class="portal-actions">${statusBadge(contract.status)}<button class="portal-button" data-print-contract="${contract.id}">PDF</button>${contract.status==='pending'?`<button class="portal-button primary" data-sign-contract="${contract.id}">Annehmen</button><button class="portal-button" data-decline-contract="${contract.id}">Ablehnen</button>`:''}</div></div>`).join(''):'<div class="portal-empty">Keine Vertragsentwürfe vorhanden.</div>'}</div></section></div>
        ${statementSection(selected.id)}
        <section class="portal-card" style="margin-top:15px"><h2>Letzte Kontobewegungen</h2><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Datum</th><th>Verwendungszweck</th><th>Betrag</th></tr></thead><tbody>${bookings.length?bookings.slice(0,10).map(entry=>`<tr><td>${date(entry.createdAt)}</td><td>${escapeHtml(entry.note)}</td><td class="${entry.direction==='credit'?'portal-kicker':''}">${entry.direction==='credit'?'+':'−'} ${money(entry.amount)}</td></tr>`).join(''):'<tr><td colspan="3" class="portal-empty">Noch keine Buchungen vorhanden.</td></tr>'}</tbody></table></div></section>
        <section class="portal-grid two" style="margin-top:15px"><section class="portal-card" id="meldungen"><h2>Problem oder Anliegen melden</h2><form class="portal-form" data-form="support-ticket">
          <input type="hidden" name="teamId" value="${selected.id}">
          <label>Kategorie<select name="category"><option>Finanzen</option><option>Vertrag</option><option>Website</option><option>Teamkonto</option><option>Sonstiges</option></select></label>
          <label>Titel<input name="subject" maxlength="100" required></label>
          <label class="full">Beschreibung<textarea name="details" maxlength="1000" required></textarea></label>
          <div class="portal-actions"><button class="portal-button primary">Meldung einreichen</button></div>
        </form></section><section class="portal-card"><h2>Deine Meldungen</h2><div class="portal-item-list">${tickets.length?tickets.slice().reverse().map(ticket=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(ticket.subject)}</strong><small>${escapeHtml(ticket.category)} · ${date(ticket.createdAt)}<br>${escapeHtml(ticket.details)}</small></div>${statusBadge(ticket.status)}</div>`).join(''):'<div class="portal-empty">Du hast noch keine Meldungen eingereicht.</div>'}</div></section></section>
        <div class="portal-warning">${window.zfcSupabase?'Rechnungen und Kontobuchungen werden synchronisiert. Vertrags- und Meldungsfunktionen sind noch lokal; tatsächliche Überweisungen erfolgen außerhalb des Portals.':'Demo-Modus: Dieses Konto ist nicht geschützt. Änderungen und Daten gelten nur für diesen Browser und sind keine echten Banktransaktionen oder rechtsgültigen Signaturen.'}</div>
      </section></main><div id="portal-toast" class="portal-toast" role="status" hidden></div></div>`;
  }

  function renderPublicOffers() {
    const container = $('[data-public-offers]');
    if (!container) return;
    const category = container.dataset.offerCategory;
    const offers = data.offers.filter(offer=>!category || (offer.category||'sponsoring')===category);
    container.innerHTML = offers.length ? offers.map(offer=>`<article class="portal-card portal-sponsor-card">
      <img src="${escapeHtml(offer.image||CATEGORY_IMAGES[offer.category]||CATEGORY_IMAGES.marketplace)}" alt="" loading="lazy"><div class="portal-kicker">${categoryName(offer.category)}</div><h2>${escapeHtml(offer.name)}</h2>
      <p>${escapeHtml(offer.description)}</p>${offer.terms?`<p class="portal-terms"><strong>Konditionen</strong><br>${escapeHtml(offer.terms)}</p>`:''}<div class="portal-stat">${money(offer.amount)}</div>
      <div class="portal-actions"><button class="portal-button primary" data-buy-offer="${offer.id}">Anfrage stellen</button>${safeUrl(offer.url)?`<a class="portal-button" href="${escapeHtml(offer.url)}" target="_blank" rel="noopener noreferrer">Mehr erfahren ↗</a>`:''}</div>
    </article>`).join('') : '<div class="portal-empty">Aktuell sind keine Angebote veröffentlicht.</div>';
  }

  function safeUrl(value) {
    try { return ['https:','http:'].includes(new URL(value).protocol); } catch { return false; }
  }

  function showPurchaseDialog(offer) {
    const dialog = $('#purchase-dialog');
    if (!dialog) return;
    $('#purchase-offer-name').textContent = offer.name;
    $('#purchase-offer-price').textContent = money(offer.amount);
    $('#purchase-offer-id').value = offer.id;
    dialog.showModal();
  }

  function makeInvoice(teamId, amount, description, dueDate, reference, orderId=null, billTo={}) {
    const number = `ZFC-${new Date().getFullYear()}-${String(data.invoices.length+1).padStart(4,'0')}`;
    const invoice = {id:uid(),number,teamId,amount,description,dueDate,reference,orderId,...billTo,status:'open',createdAt:new Date().toISOString()};
    data.invoices.push(invoice);
    return invoice;
  }

  function cents(value) {
    const amount = Math.round(Number(value)*100);
    if (!Number.isSafeInteger(amount) || amount <= 0 || amount > 100000000000) throw new Error('Bitte einen gültigen Betrag eingeben.');
    return amount;
  }

  function nonNegativeCents(value) {
    const amount = Math.round(Number(value)*100);
    if (!Number.isSafeInteger(amount) || amount < 0 || amount > 100000000000) throw new Error('Bitte einen gültigen Betrag ab null eingeben.');
    return amount;
  }

  async function handleForm(form) {
    const fields = Object.fromEntries(new FormData(form));
    if (form.dataset.form==='record-edit') {
      const {recordType:type,recordId:id} = form.dataset;
      const collections = {offer:data.offers,order:data.orders,invoice:data.invoices,contract:data.contracts,booking:data.bookings,ticket:data.tickets};
      const item = collections[type]?.find(entry=>entry.id===id);
      if (!item) throw new Error('Der Eintrag wurde nicht gefunden.');
      const amount = ['offer','order','invoice','booking'].includes(type)?cents(fields.amount):null;
      const teamId = fields.teamId || item.teamId;
      if (!teams.some(team=>team.id===teamId)) throw new Error('Bitte ein gültiges Team auswählen.');
      let table, payload, updated;
      if (type==='offer') {
        if (!fields.name.trim() || !fields.description.trim()) throw new Error('Name und Kurzbeschreibung dürfen nicht leer sein.');
        if (fields.url && !safeUrl(fields.url)) throw new Error('Bitte eine gültige http(s)-URL eingeben.');
        if (fields.image && !safeUrl(fields.image) && !fields.image.startsWith('data:image/') && fields.image!==item.image) throw new Error('Bitte eine gültige http(s)-Bild-URL eingeben.');
        const newImage=form.querySelector('[name="imageFile"]')?.dataset.image;
        updated={...item,name:fields.name.trim(),category:fields.category,amount,description:fields.description.trim(),terms:fields.terms.trim(),url:fields.url.trim(),image:newImage||fields.image.trim()||(item.image?.startsWith('data:')?item.image:''),published:fields.published==='published'};
        table='sponsor_offers';
        payload={name:updated.name,category:updated.category,amount_cents:amount,description:updated.description,terms:updated.terms,target_url:updated.url||null,image_path:updated.image||null,published:updated.published};
      } else if (type==='order') {
        if (!fields.offerName.trim() || !fields.contactName.trim() || !fields.email.trim()) throw new Error('Angebot, Kontakt und E-Mail dürfen nicht leer sein.');
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fields.email.trim())) throw new Error('Bitte eine gültige E-Mail-Adresse eingeben.');
        updated={...item,teamId,offerName:fields.offerName.trim(),category:fields.category,amount,contactName:fields.contactName.trim(),email:fields.email.trim(),company:fields.company.trim(),billingAddress:fields.billingAddress.trim(),notes:fields.notes.trim(),adminNotes:fields.adminNotes.trim(),status:fields.status};
        table='sponsor_orders';
        payload={team_id:teamId,offer_name:updated.offerName,category:updated.category,amount_cents:amount,contact_name:updated.contactName,email:updated.email,company:updated.company,billing_address:updated.billingAddress,customer_notes:updated.notes,admin_notes:updated.adminNotes,status:updated.status};
      } else if (type==='invoice') {
        if (!fields.number.trim() || !fields.description.trim() || !fields.dueDate) throw new Error('Nummer, Beschreibung und Fälligkeitsdatum sind erforderlich.');
        if (item.status==='paid' && fields.status!=='paid') throw new Error('Eine bezahlte Rechnung kann hier nicht zurückgesetzt werden.');
        if (fields.status==='paid' && item.status!=='paid') throw new Error('Bitte nutze „Zahlung bestätigen“, damit das Teamkonto korrekt belastet wird.');
        updated={...item,teamId,number:fields.number.trim(),description:fields.description.trim(),amount,dueDate:fields.dueDate,reference:fields.reference.trim(),billToName:fields.billToName.trim(),billToEmail:fields.billToEmail.trim(),billToCompany:fields.billToCompany.trim(),billToAddress:fields.billToAddress.trim(),status:fields.status};
        table='invoices';
        payload={team_id:teamId,invoice_number:updated.number,description:updated.description,amount_cents:amount,due_date:updated.dueDate,reference:updated.reference,bill_to_name:updated.billToName,bill_to_email:updated.billToEmail,bill_to_company:updated.billToCompany,bill_to_address:updated.billToAddress,status:updated.status};
      } else if (type==='contract') {
        if (!fields.title.trim() || !fields.terms.trim() || !fields.endDate) throw new Error('Titel, Konditionen und Enddatum sind erforderlich.');
        updated={...item,teamId,type:fields.type,title:fields.title.trim(),terms:fields.terms.trim(),endDate:fields.endDate,status:fields.status};
        table='contracts';
        payload={team_id:teamId,type:updated.type,title:updated.title,terms:updated.terms,ends_on:updated.endDate,status:updated.status};
      } else if (type==='booking') {
        if (!fields.note.trim()) throw new Error('Der Verwendungszweck darf nicht leer sein.');
        const originalEffect=item.direction==='credit'?item.amount:-item.amount;
        if (fields.direction==='debit' && balance(teamId)-(item.teamId===teamId?originalEffect:0)<amount) throw new Error('Das Ziel-Teamkonto hat für diese Belastung nicht genügend Guthaben.');
        updated={...item,teamId,direction:fields.direction,amount,note:fields.note.trim()};
        table='account_entries';
        payload={team_id:teamId,direction:updated.direction,amount_cents:amount,description:updated.note};
      } else if (type==='ticket') {
        if (!fields.category.trim() || !fields.subject.trim() || !fields.details.trim()) throw new Error('Kategorie, Titel und Beschreibung sind erforderlich.');
        updated={...item,teamId,category:fields.category.trim(),subject:fields.subject.trim(),details:fields.details.trim(),status:fields.status};
        table='support_tickets';
        payload={team_id:teamId,category:updated.category,subject:updated.subject,details:updated.details,status:updated.status};
      } else {
        throw new Error('Dieser Eintragstyp kann nicht bearbeitet werden.');
      }
      if (window.zfcSupabase) {
        const {error}=await window.zfcSupabase.from(table).update(payload).eq('id',id);
        if (error) throw new Error(`Änderungen konnten nicht gespeichert werden: ${error.message}`);
      }
      collections[type]=collections[type].map(entry=>entry.id===id?updated:entry);
      if (type==='offer') data.offers=collections[type];
      if (type==='order') data.orders=collections[type];
      if (type==='invoice') data.invoices=collections[type];
      if (type==='contract') data.contracts=collections[type];
      if (type==='booking') data.bookings=collections[type];
      if (type==='ticket') data.tickets=collections[type];
      const dialog=$('#record-editor');
      if (dialog?.open) dialog.close();
      if(save()) {renderAdminTab(type==='offer'?'offers':type==='order'?'orders':type==='contract'?'contracts':type==='ticket'?'tickets':'finance');showToast('Änderungen gespeichert.');}
    } else if (form.dataset.form==='home') {
      data.home.title = fields.title.trim();
      data.home.claim = fields.claim.trim();
      data.home.intro = fields.intro.trim();
      data.home.image = form.querySelector('[name="imageFile"]').dataset.image || (fields.gallery==='upload'?data.home.image:fields.gallery);
      if (save()) { applyHome(); showToast('Startseite gespeichert.'); }
    } else if (form.dataset.form==='team-logo') {
      const fileInput=form.querySelector('[name="imageFile"]');
      const image=fileInput.dataset.image;
      if(image) data.teamLogos[fields.teamId]=image;
      else delete data.teamLogos[fields.teamId];
      if(save()){renderAdminTab('content');showToast(image?`Eigenes Teamlogo für ${teamName(fields.teamId)} gespeichert.`:`Team-Badge für ${teamName(fields.teamId)} wiederhergestellt.`);}
    } else if (form.dataset.form==='offer') {
      if (fields.url && !safeUrl(fields.url)) throw new Error('Bitte eine gültige http(s)-URL eingeben.');
      const amount = cents(fields.amount);
      const image = form.querySelector('[name="imageFile"]').dataset.image || (fields.gallery==='upload'?'':fields.gallery);
      if (window.zfcSupabase) {
        const {data: row, error} = await window.zfcSupabase.from('sponsor_offers').insert({
          category:fields.category,name:fields.name.trim(),description:fields.description.trim(),terms:fields.terms.trim(),target_url:fields.url.trim()||null,
          amount_cents:amount,image_path:image||null,published:true,created_by:window.zfcProfile.id
        }).select('*').single();
        if (error) throw new Error(`Angebot konnte nicht veröffentlicht werden: ${error.message}`);
        data.offers.unshift(mapOffer(row));
      } else {
        data.offers.push({id:uid(),category:fields.category,name:fields.name.trim(),description:fields.description.trim(),terms:fields.terms.trim(),url:fields.url.trim(),amount,image,createdAt:new Date().toISOString()});
      }
      if (save()) { renderAdminTab('offers'); showToast('Angebot veröffentlicht.'); }
    } else if (form.dataset.form==='invoice') {
      const amount = cents(fields.amount);
      let invoice;
      if (window.zfcSupabase) {
        const invoiceNumber = `ZFC-${new Date().getFullYear()}-${uid().slice(0,8).toUpperCase()}`;
        const {data: row,error} = await window.zfcSupabase.from('invoices').insert({
          team_id:fields.teamId,invoice_number:invoiceNumber,description:fields.description.trim(),amount_cents:amount,
          due_date:fields.dueDate,reference:fields.reference.trim(),bill_to_name:fields.billToName.trim(),
          bill_to_email:fields.billToEmail.trim(),bill_to_company:fields.billToCompany.trim(),bill_to_address:fields.billToAddress.trim(),
          created_by:window.zfcProfile.id
        }).select('*').single();
        if (error) throw new Error(`Rechnung konnte nicht erstellt werden: ${error.message}`);
        invoice=mapInvoice(row);data.invoices.unshift(invoice);
      } else {
        invoice = makeInvoice(fields.teamId,amount,fields.description.trim(),fields.dueDate,fields.reference.trim(),null,{billToName:fields.billToName,billToEmail:fields.billToEmail,billToCompany:fields.billToCompany,billToAddress:fields.billToAddress});
      }
      if (save()) { renderAdminTab('finance'); showToast(`Rechnung ${invoice.number} erstellt.`); }
    } else if (form.dataset.form==='booking') {
      const amount = cents(fields.amount);
      if (!window.zfcSupabase && fields.direction==='debit' && balance(fields.teamId)<amount) throw new Error('Das Teamkonto hat dafür nicht genügend Guthaben.');
      let booking = {id:uid(),teamId:fields.teamId,direction:fields.direction,amount,note:fields.note.trim(),createdAt:new Date().toISOString()};
      if (window.zfcSupabase) {
        const {data: row,error} = await window.zfcSupabase.from('account_entries').insert({team_id:fields.teamId,direction:fields.direction,amount_cents:amount,description:fields.note.trim(),created_by:window.zfcProfile.id}).select('*').single();
        if (error) throw new Error('Buchung fehlgeschlagen. Bitte Kontostand und Angaben prüfen.');
        booking={id:row.id,teamId:row.team_id,direction:row.direction,amount:Number(row.amount_cents),note:row.description,createdAt:row.created_at};
      }
      data.bookings.unshift(booking);
      if (save()) { renderAdminTab('finance'); showToast('Buchung erfasst.'); }
    } else if (form.dataset.form==='contract') {
      let contract={id:uid(),teamId:fields.teamId,type:fields.type,title:fields.title.trim(),terms:fields.terms.trim(),endDate:fields.endDate,status:'pending',createdAt:new Date().toISOString()};
      if (window.zfcSupabase) {
        const {data:row,error}=await window.zfcSupabase.from('contracts').insert({team_id:contract.teamId,type:contract.type,title:contract.title,terms:contract.terms,ends_on:contract.endDate,status:'pending',created_by:window.zfcProfile.id}).select('*').single();
        if(error) throw new Error(`Vertrag konnte nicht gespeichert werden: ${error.message}`);
        contract=mapContract(row);
      }
      data.contracts.push(contract);
      if (save()) { renderAdminTab(form.dataset.returnTab||'contracts'); showToast('Vertrag zur Prüfung gesendet.'); }
    } else if (form.dataset.form==='support-ticket') {
      let ticket={id:uid(),teamId:fields.teamId,category:fields.category,subject:fields.subject.trim(),details:fields.details.trim(),status:'open',createdAt:new Date().toISOString()};
      if(window.zfcSupabase) {
        const {data:row,error}=await window.zfcSupabase.from('support_tickets').insert({team_id:ticket.teamId,category:ticket.category,subject:ticket.subject,details:ticket.details,status:'open',created_by:window.zfcProfile.id}).select('*').single();
        if(error) throw new Error(`Meldung konnte nicht gespeichert werden: ${error.message}`);
        ticket=mapTicket(row);
      }
      data.tickets.push(ticket);
      if (save()) { renderTeam(fields.teamId); showToast('Meldung wurde eingereicht.'); }
    } else if (form.dataset.form==='purchase') {
      const offer = data.offers.find(item=>item.id===fields.offerId);
      if (!offer) throw new Error('Dieses Angebot ist nicht mehr verfügbar.');
      const email = fields.email.trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Bitte eine gültige E-Mail-Adresse eingeben.');
      if (window.zfcSupabase) {
        const { error } = await window.zfcSupabase.functions.invoke('public-purchase', {body:{offerId:offer.id,teamId:fields.teamId,contactName:fields.contactName,email,company:fields.company||'',billingAddress:fields.billingAddress||'',notes:fields.notes||''}});
        if (error) throw new Error('Anfrage konnte nicht gesendet werden. Bitte später erneut versuchen.');
        form.closest('dialog').close(); form.reset(); showToast('Anfrage wurde an die Verwaltung gesendet.');
        return;
      }
      data.orders.push({id:uid(),offerId:offer.id,offerName:offer.name,category:offer.category||'sponsoring',terms:offer.terms||'',amount:offer.amount,teamId:fields.teamId,contactName:fields.contactName.trim(),email,company:(fields.company||'').trim(),billingAddress:(fields.billingAddress||'').trim(),notes:(fields.notes||'').trim(),status:'pending',createdAt:new Date().toISOString()});
      if (save()) { form.closest('dialog').close(); form.reset(); showToast('Anfrage wurde als Sponsoren-Akte vorgemerkt.'); }
    }
  }

  function invoicePrint(invoice) {
    const team = teams.find(entry=>entry.id===invoice.teamId);
    const recipient = [invoice.billToCompany,invoice.billToName,invoice.billToEmail,invoice.billToAddress]
      .filter(Boolean).map(value=>escapeHtml(value).replace(/\n/g,'<br>')).join('<br>') || escapeHtml(team.name);
    const statusText = {open:'Offen',payment_requested:'Zahlung vorgemerkt',paid:'Bezahlt',void:'Storniert'}[invoice.status] || invoice.status;
    openDocument('Rechnung', invoice.number, `<h1>Rechnung</h1><p class="subtitle">Status: ${escapeHtml(statusText)}</p>
      <div class="parties"><div class="party"><small>Rechnung an</small>${recipient}</div><div class="party"><small>Rechnungsdetails</small>Rechnungsnummer: <b>${escapeHtml(invoice.number)}</b><br>Rechnungsdatum: ${date(invoice.createdAt)}<br>Fällig am: ${date(invoice.dueDate)}<br>Team: ${escapeHtml(team.name)}<br>Referenz: ${escapeHtml(invoice.reference||'—')}</div></div>
      <table><thead><tr><th>Pos.</th><th>Beschreibung</th><th class="num">Betrag</th></tr></thead><tbody><tr><td>1</td><td>${escapeHtml(invoice.description)}</td><td class="num">${money(invoice.amount)}</td></tr><tr class="sum"><td colspan="2">Gesamtbetrag (EUR)</td><td class="num">${money(invoice.amount)}</td></tr></tbody></table>
      <p>Bitte begleiche den Betrag bis zum ${date(invoice.dueDate)} unter Angabe der Rechnungsnummer.</p>
      <p class="note">Rechnungsentwurf zur Prüfung: Vor Versand sind die vollständigen Angaben des Rechnungsausstellers sowie die geltenden Rechnungsanforderungen zu ergänzen. Zahlung und Überweisung erfolgen außerhalb dieses Portals.</p>`, date(invoice.createdAt));
  }

  function applyHome() {
    if (!data?.home) return;
    const title = $('[data-home-title]'), claim = $('[data-home-claim]'), intro = $('[data-home-intro]'), image = $('[data-home-image]');
    if (title) title.textContent = data.home.title;
    if (claim) claim.textContent = data.home.claim;
    if (intro) intro.textContent = data.home.intro;
    if (image && (data.home.image?.startsWith('https://') || data.home.image?.startsWith('data:image/'))) image.src = data.home.image;
  }

  function mapOffer(row) {
    return {id:row.id,category:row.category||'sponsoring',name:row.name,description:row.description,terms:row.terms||'',url:row.target_url||'',amount:Number(row.amount_cents),image:row.image_path||'',published:row.published,createdAt:row.created_at};
  }

  function mapOrder(row) {
    return {id:row.id,offerId:row.offer_id,offerName:row.offer_name,category:row.category||'sponsoring',terms:row.offer_terms||'',amount:Number(row.amount_cents),teamId:row.team_id,contactName:row.contact_name,email:row.email,company:row.company||'',billingAddress:row.billing_address||'',notes:row.customer_notes||'',adminNotes:row.admin_notes||'',status:row.status,createdAt:row.created_at};
  }

  function mapInvoice(row) {
    return {id:row.id,number:row.invoice_number,teamId:row.team_id,amount:Number(row.amount_cents),description:row.description,dueDate:row.due_date,reference:row.reference||'',orderId:row.order_id,billToName:row.bill_to_name||'',billToEmail:row.bill_to_email||'',billToCompany:row.bill_to_company||'',billToAddress:row.bill_to_address||'',status:row.status,createdAt:row.created_at};
  }

  function mapContract(row) {
    return {id:row.id,teamId:row.team_id,type:row.type,title:row.title,terms:row.terms,endDate:row.ends_on,status:row.status,createdAt:row.created_at};
  }

  function mapTicket(row) {
    return {id:row.id,teamId:row.team_id,category:row.category,subject:row.subject,details:row.details,status:row.status,createdAt:row.created_at};
  }

  async function loadSharedRecords(page) {
    if (!window.zfcSupabase) return;
    const requestedTeamId = new URLSearchParams(location.search).get('team');
    const selectedTeamId = window.zfcProfile?.role==='team_chief'
      ? window.zfcProfile.team_id
      : (teams.some(team=>team.id===requestedTeamId)?requestedTeamId:teams[0].id);
    if (page==='admin' || page==='team') {
      const {data: teamRows, error: teamError} = await window.zfcSupabase.from('teams').select('id,initial_balance_cents');
      if (teamError) throw teamError;
      teamRows.forEach(row=>{const team=teams.find(item=>item.id===row.id);if(team)team.initialBalance=Number(row.initial_balance_cents);});
      let entriesQuery = window.zfcSupabase.from('account_entries').select('*').order('created_at',{ascending:false});
      if (page==='team') entriesQuery=entriesQuery.eq('team_id',selectedTeamId);
      const {data: entryRows,error: entriesError}=await entriesQuery;
      if (entriesError) throw entriesError;
      data.bookings=entryRows.map(row=>({id:row.id,teamId:row.team_id,direction:row.direction,amount:Number(row.amount_cents),note:row.description,createdAt:row.created_at}));
    }
    let offersQuery = window.zfcSupabase.from('sponsor_offers').select('*');
    if(page!=='admin') offersQuery=offersQuery.eq('published',true);
    const {data: offerRows, error: offerError} = await offersQuery.order('created_at', {ascending:false});
    if (offerError) throw offerError;
    data.offers = offerRows.map(mapOffer);
    if (page === 'admin') {
      const [{data: orderRows, error: orderError}, {data: invoiceRows, error: invoiceError}, {data: profileRows, error: profilesError},{data: contractRows,error:contractsError},{data: ticketRows,error:ticketsError}] = await Promise.all([
        window.zfcSupabase.from('sponsor_orders').select('*').order('created_at', {ascending:false}),
        window.zfcSupabase.from('invoices').select('*').order('created_at', {ascending:false}),
        window.zfcSupabase.from('profiles').select('id,email,display_name,role,team_id').order('created_at', {ascending:false}),
        window.zfcSupabase.from('contracts').select('*').order('created_at',{ascending:false}),
        window.zfcSupabase.from('support_tickets').select('*').order('created_at',{ascending:false})
      ]);
      if (orderError) throw orderError;
      if (invoiceError) throw invoiceError;
      if (profilesError) throw profilesError;
      if (contractsError) throw contractsError;
      if (ticketsError) throw ticketsError;
      data.orders = orderRows.map(mapOrder);
      data.invoices = invoiceRows.map(mapInvoice);
      data.contracts = contractRows.map(mapContract);
      data.tickets = ticketRows.map(mapTicket);
      adminProfiles = profileRows;
    } else if (page === 'team') {
      const [{data:invoiceRows,error:invoiceError},{data:contractRows,error:contractError},{data:ticketRows,error:ticketError}] = await Promise.all([
        window.zfcSupabase.from('invoices').select('*').eq('team_id', selectedTeamId).order('created_at', {ascending:false}),
        window.zfcSupabase.from('contracts').select('*').eq('team_id',selectedTeamId).order('created_at',{ascending:false}),
        window.zfcSupabase.from('support_tickets').select('*').eq('team_id',selectedTeamId).order('created_at',{ascending:false})
      ]);
      if (invoiceError) throw invoiceError;
      if (contractError) throw contractError;
      if (ticketError) throw ticketError;
      data.invoices = invoiceRows.map(mapInvoice);
      data.contracts=contractRows.map(mapContract);
      data.tickets=ticketRows.map(mapTicket);
    }
  }

  async function init() {
    const root = $('#portal-root');
    const page = root?.dataset.portalPage;
    const auth = window.zfcAuthorizePortal ? await window.zfcAuthorizePortal() : null;
    if (window.zfcSupabase && page && !auth) return;
    try {
      data = load();
      if(data.home.title==='Built to race.' && data.home.claim==='Made to rise.'){
        Object.assign(data.home,{title:'Herzlich willkommen',claim:'bei ZFC.',intro:'Entdecke Angebote und Möglichkeiten rund um unsere Teams. Wähle den Bereich, der dich interessiert.'});
      }
      if(data.home.image?.includes('photo-1532906619279-a4b7267faa66')) data.home.image=GALLERY_IMAGE;
      await loadSharedRecords(page);
    } catch (error) {
      if (root) root.innerHTML = `<main class="portal-main"><div class="portal-warning">${escapeHtml(error.message)}</div></main>`;
      return;
    }
    applyHome();
    document.querySelectorAll('[data-storage-warning]').forEach(element=>{
      element.textContent = window.zfcSupabase
        ? 'Anfragen werden an die Verwaltung übermittelt. Die Anfrage ist unverbindlich; Vertrag und Zahlung werden separat bestätigt.'
        : 'Demo-Modus: Anfragen werden nur in diesem Browser gespeichert. Für die zentrale Bearbeitung muss Supabase eingerichtet sein.';
    });
    document.querySelectorAll('#purchase-dialog select[name="teamId"]').forEach(select=>{select.innerHTML=teamOptions();});
    renderPublicOffers();
    if (page==='admin') renderAdminTab();
    if (page==='team') renderTeam(window.zfcProfile?.team_id || new URLSearchParams(location.search).get('team') || teams[0].id);
  }

  document.addEventListener('click', async event => {
    const button = event.target.closest('[data-admin-tab]');
    if (button && $('#portal-root')) { renderAdminTab(button.dataset.adminTab); return; }
    const editRecord = event.target.closest('[data-edit-record]');
    if (editRecord) { openRecordEditor(editRecord.dataset.editRecord, editRecord.dataset.recordId); return; }
    if (event.target.closest('[data-close-editor]')) { $('#record-editor')?.close(); return; }
    const printContract = event.target.closest('[data-print-contract]');
    if (printContract) { const item=data.contracts.find(entry=>entry.id===printContract.dataset.printContract);if(item)contractPrint(item);return; }
    const printStatement = event.target.closest('[data-print-statement]');
    if (printStatement) { statementPrint(printStatement.dataset.printStatement, statementMonth); return; }
    const refreshProfiles = event.target.closest('[data-refresh-profiles]');
    if (refreshProfiles) {
      refreshProfiles.disabled = true;
      const {data: profiles, error} = await window.zfcSupabase.from('profiles')
        .select('id,email,display_name,role,team_id').order('created_at', {ascending:false});
      if (error) {
        refreshProfiles.disabled = false;
        showToast('Profile konnten nicht geladen werden. Prüfe die Supabase-RLS-Richtlinie.',true);
        return;
      }
      adminProfiles=profiles;
      renderAdminTab('accounts');
      showToast('Profile aktualisiert.');
      return;
    }
    const saveProfileRole = event.target.closest('[data-save-profile-role]');
    if (saveProfileRole) {
      const row = saveProfileRole.closest('[data-profile-row]');
      const role = row.querySelector('[data-user-role]').value;
      const teamId = role==='team_chief' ? row.querySelector('[data-user-team]').value : null;
      saveProfileRole.disabled = true;
      const {data: result, error} = await window.zfcSupabase.functions.invoke('admin-assign-role', {
        body:{profileId:saveProfileRole.dataset.saveProfileRole,role,teamId}
      });
      if (error) {
        saveProfileRole.disabled = false;
        showToast('Rolle konnte nicht gespeichert werden. Prüfe, ob admin-assign-role deployed ist.',true);
        return;
      }
      adminProfiles=adminProfiles.map(profile=>profile.id===result.profile.id?result.profile:profile);
      renderAdminTab('accounts');
      showToast('Rolle und Team wurden gespeichert.');
      return;
    }
    const buy = event.target.closest('[data-buy-offer]');
    if (buy) { const offer=data.offers.find(item=>item.id===buy.dataset.buyOffer); if(offer)showPurchaseDialog(offer); return; }
    const approve = event.target.closest('[data-approve-order]');
    if (approve) {
      const order=data.orders.find(item=>item.id===approve.dataset.approveOrder);
      if(order?.status==='pending'){
        try {
          if (window.zfcSupabase) {
            const invoiceNumber = `ZFC-${new Date().getFullYear()}-${uid().slice(0,8).toUpperCase()}`;
            const dueDate = new Date(Date.now()+30*86400000).toISOString().slice(0,10);
            const {data: invoiceRow, error: invoiceError} = await window.zfcSupabase.from('invoices').insert({
              team_id:order.teamId,order_id:order.id,invoice_number:invoiceNumber,
              description:`${categoryName(order.category)}: ${order.offerName}`,amount_cents:order.amount,
              due_date:dueDate,reference:order.id,bill_to_name:order.contactName,bill_to_email:order.email,
              bill_to_company:order.company,bill_to_address:order.billingAddress,created_by:window.zfcProfile.id
            }).select('*').single();
            if (invoiceError) throw invoiceError;
            const {error: orderError} = await window.zfcSupabase.from('sponsor_orders').update({status:'approved'}).eq('id',order.id);
            if (orderError) {
              await window.zfcSupabase.from('invoices').delete().eq('id',invoiceRow.id);
              throw orderError;
            }
            data.invoices.unshift(mapInvoice(invoiceRow));
          } else {
            makeInvoice(order.teamId,order.amount,`${categoryName(order.category)}: ${order.offerName}`,new Date(Date.now()+30*86400000).toISOString().slice(0,10),order.id,order.id,{billToName:order.contactName,billToEmail:order.email,billToCompany:order.company,billToAddress:order.billingAddress});
          }
          order.status='approved';
          save();renderAdminTab('orders');showToast('Anfrage geprüft und Rechnung erstellt.');
        } catch { showToast('Rechnung konnte nicht erstellt werden.',true); }
      }
      return;
    }
    const removeOffer = event.target.closest('[data-delete-offer]');
    if (removeOffer && confirm('Dieses veröffentlichte Angebot entfernen?')) {
      try {
        if (window.zfcSupabase) {
          const {error} = await window.zfcSupabase.from('sponsor_offers').delete().eq('id',removeOffer.dataset.deleteOffer);
          if (error) throw error;
        }
        data.offers=data.offers.filter(item=>item.id!==removeOffer.dataset.deleteOffer);
        if(save()){renderAdminTab('offers');showToast('Angebot entfernt.');}
      } catch (error) { showToast(`Angebot konnte nicht entfernt werden: ${error.message||''}`,true); }
      return;
    }
    const ticketButton = event.target.closest('[data-ticket-status]');
    if (ticketButton) {
      const ticket=data.tickets.find(item=>item.id===ticketButton.dataset.ticketStatus);
      if(ticket){
        if (window.zfcSupabase) {
          const {error}=await window.zfcSupabase.from('support_tickets').update({status:ticketButton.dataset.nextStatus}).eq('id',ticket.id);
          if (error) { showToast(`Status konnte nicht gespeichert werden: ${error.message}`,true); return; }
        }
        ticket.status=ticketButton.dataset.nextStatus;
        if(save()){renderAdminTab('tickets');showToast('Meldungsstatus aktualisiert.');}
      }
      return;
    }
    const payment = event.target.closest('[data-request-payment]');
    if (payment) {
      const invoice=data.invoices.find(item=>item.id===payment.dataset.requestPayment);
      if(invoice?.status==='open'){
        try {
          if (window.zfcSupabase) {
            const {error} = await window.zfcSupabase.rpc('request_invoice_payment',{p_invoice_id:invoice.id});
            if (error) throw error;
          }
          invoice.status='payment_requested';save();renderTeam(currentTeamId);showToast('Zahlung beim Admin vorgemerkt.');
        } catch { showToast('Zahlungsanfrage konnte nicht gesendet werden.',true); }
      }
      return;
    }
    const confirmPayment = event.target.closest('[data-confirm-payment]');
    if (confirmPayment) {
      const invoice=data.invoices.find(item=>item.id===confirmPayment.dataset.confirmPayment);
      if(invoice?.status==='payment_requested'){
        try {
          if (window.zfcSupabase) {
            const {error} = await window.zfcSupabase.from('invoices').update({status:'paid'}).eq('id',invoice.id);
            if (error) throw error;
            data.bookings.unshift({id:uid(),teamId:invoice.teamId,direction:'debit',amount:invoice.amount,note:`Rechnung ${invoice.number}`,createdAt:new Date().toISOString()});
          } else {
            if(balance(invoice.teamId)<invoice.amount){showToast('Kontostand reicht für diese Zahlung nicht aus. Bitte zuerst eine Gutschrift buchen.',true);return;}
            data.bookings.push({id:uid(),teamId:invoice.teamId,direction:'debit',amount:invoice.amount,note:`Rechnung ${invoice.number}`,createdAt:new Date().toISOString()});
          }
          invoice.status='paid';save();renderAdminTab('finance');showToast('Zahlung bestätigt und Teamkonto belastet.');
        } catch { showToast('Zahlungsstatus konnte nicht aktualisiert werden.',true); }
      }
      return;
    }
    const contract = event.target.closest('[data-sign-contract],[data-decline-contract]');
    if (contract) { const item=data.contracts.find(entry=>entry.id===(contract.dataset.signContract||contract.dataset.declineContract));if(item?.status==='pending'){
        const accept=Boolean(contract.dataset.signContract);
        if (window.zfcSupabase) {
          const {error}=await window.zfcSupabase.rpc('respond_to_contract',{p_contract_id:item.id,p_accept:accept});
          if (error) { showToast(`Antwort konnte nicht gespeichert werden: ${error.message}`,true); return; }
        }
        item.status=accept?'signed':'declined';
        if(save()){renderTeam(currentTeamId);showToast(accept?'Vertrag angenommen.':'Vertrag abgelehnt.');}
      }
      return; }
    const print = event.target.closest('[data-print-invoice]');
    if (print) { const invoice=data.invoices.find(item=>item.id===print.dataset.printInvoice);if(invoice)invoicePrint(invoice); }
  });

  document.addEventListener('change', event => {
    if (event.target.matches('[data-team-picker]')) { renderTeam(event.target.value); return; }
    if (event.target.matches('[data-ebank-team]')) { adminTeamId=event.target.value; renderAdminTab('ebanking'); return; }
    if (event.target.matches('[data-statement-month]')) {
      if (!event.target.value) return;
      statementMonth=event.target.value;
      if ($('#portal-root')?.dataset.portalPage==='admin') renderAdminTab('ebanking'); else renderTeam(currentTeamId);
      return;
    }
    if (event.target.matches('[data-user-role]')) {
      const row = event.target.closest('[data-profile-row]');
      const teamControl = row?.querySelector('[data-user-team]');
      if (teamControl) teamControl.disabled = event.target.value==='admin';
      return;
    }
    if (event.target.matches('[name="gallery"]')) {
      const form=event.target.form, file=form.querySelector('[name="imageFile"]');
      if(event.target.value!=='upload'){file.dataset.image='';const preview=form.querySelector('[data-home-preview]');if(preview)preview.src=event.target.value;}
    }
    if (event.target.matches('[name="imageFile"]') && event.target.files[0]) {
      const file=event.target.files[0], form=event.target.form;
      if(!file.type.startsWith('image/')){showToast('Bitte eine Bilddatei auswählen.',true);event.target.value='';return;}
      readImage(file).then(result=>{event.target.dataset.image=result;const preview=form.querySelector('[data-home-preview]');if(preview)preview.src=result;}).catch(()=>showToast('Bild konnte nicht gelesen werden.',true));
    }
  });

  document.addEventListener('submit', async event => {
    const form=event.target.closest('[data-form]');
    if (!form) return;
    event.preventDefault();
    try { await handleForm(form); } catch (error) { showToast(error.message,true); }
  });

  init();
})();
