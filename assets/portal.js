'use strict';

(() => {
  const STORAGE_KEY = 'zfc-portal-v1';
  const GALLERY_IMAGE = 'https://images.unsplash.com/photo-1532906619279-a4b7267faa66?auto=format&fit=crop&w=1400&q=85';
  const teams = [
    {id:'scuderia-rosso',name:'Scuderia Rosso',mark:'SR',color:'#e51e2a'},
    {id:'apex-motorsport',name:'Apex Motorsport',mark:'AM',color:'#d7dfeb'},
    {id:'veloce-racing',name:'Veloce Racing',mark:'VR',color:'#f0b429'},
    {id:'northstar-gp',name:'Northstar GP',mark:'NG',color:'#60a5fa'},
    {id:'vector-racing',name:'Vector Racing',mark:'VX',color:'#c7f36b'},
    {id:'ironclad-racing',name:'Ironclad Racing',mark:'IR',color:'#a8b6c5'},
    {id:'pulse-motorsport',name:'Pulse Motorsport',mark:'PM',color:'#ea668f'},
    {id:'cobalt-works',name:'Cobalt Works',mark:'CW',color:'#5688ff'},
    {id:'summit-gp',name:'Summit GP',mark:'SG',color:'#a1cb88'},
    {id:'atlas-competition',name:'Atlas Competition',mark:'AC',color:'#ef995d'}
  ];
  const money = cents => new Intl.NumberFormat('de-DE',{style:'currency',currency:'EUR'}).format((Number(cents)||0)/100);
  const date = value => new Intl.DateTimeFormat('de-CH',{dateStyle:'medium'}).format(new Date(value));
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
  const uid = () => crypto.randomUUID();
  const $ = (selector, root=document) => root.querySelector(selector);
  const teamName = id => teams.find(team => team.id === id)?.name || 'Unbekanntes Team';
  const categoryName = (category='sponsoring') => ({insurance:'Insurance',sponsoring:'Sponsoring',hq:'HQ',marketplace:'Marketplace'})[category] || 'Marketplace';
  const emptyData = () => ({home:{title:'Herzlich willkommen',claim:'bei ZFC.',intro:'Entdecke Angebote und Möglichkeiten rund um unsere Teams. Wähle den Bereich, der dich interessiert.',image:GALLERY_IMAGE},teamLogos:{},offers:[],orders:[],invoices:[],contracts:[],bookings:[],tickets:[]});
  let data, currentTeamId;

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
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
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
      ['overview','Übersicht'],['content','Startseite & Galaxy'],['offers','Angebote'],['orders','Kaufanfragen'],['finance','Teamkonten & Rechnungen'],['contracts','Verträge'],['accounts','Benutzer & Rollen'],['tickets','Probleme & Meldungen']
    ];
    return `<div class="portal-shell"><aside class="portal-sidebar">
      <a class="portal-brand" href="../index.html"><span class="portal-brand-mark">Z</span><span><strong>ZFC</strong><small>TEAM MANAGEMENT</small></span></a>
      <div class="portal-label">Arbeitsbereich</div><nav class="portal-nav" aria-label="Admin Navigation">${navigation.map(([key,label])=>`<button type="button" data-admin-tab="${key}" class="${active===key?'active':''}">${label}</button>`).join('')}</nav>
      <div class="portal-side-note">Admin Control Center<br><a href="../index.html">← Zur öffentlichen Website</a></div>
    </aside><main class="portal-main"><div class="portal-topbar"><div><strong>${escapeHtml(title)}</strong><br><small>Verwaltung · Saison 2026</small></div><div class="portal-actions">${window.zfcSupabase?'':'<span class="portal-badge pending">Lokale Demo</span>'}<button class="portal-button" type="button" data-sign-out>Abmelden</button></div></div>${content}</main><div id="portal-toast" class="portal-toast" role="status" hidden></div></div>`;
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
          <article class="portal-card"><div class="portal-label-text">Teams im Grid</div><div class="portal-stat">10</div><div class="portal-label-text">Teamkonten verwalten</div></article>
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
          <label class="full">Eigenes Bild (optional)<input name="imageFile" type="file" accept="image/*"><small class="portal-muted">Auswahl aus der Gerätegalerie. Maximal 600 KB; das Bild bleibt in diesem Browser.</small></label>
          <img class="portal-gallery-preview" data-home-preview src="${escapeHtml(data.home.image || GALLERY_IMAGE)}" alt="Vorschau des Startseitenbilds">
          <div class="portal-actions"><button class="portal-button primary">Startseite speichern</button></div>
        </form></section>
        <section class="portal-card" style="margin-top:15px"><h2>Teamlogos im E-Banking</h2><form class="portal-form" data-form="team-logo">
          <label>Team${teamSelect()}</label>
          <label>Logo aus der Gerätegalerie<input name="imageFile" type="file" accept="image/*" required><small class="portal-muted">PNG, JPG oder WebP · maximal 600 KB.</small></label>
          <div class="portal-actions"><button class="portal-button">Teamlogo speichern</button></div>
        </form></section>`;
    } else if (tab==='offers') {
      content = `${heading('Sponsorenshop','Sponsoring-Angebote erstellen','URL, Bild, Kurzbeschreibung und Preis werden im öffentlichen Sponsorenbereich angezeigt.')}
        <div class="portal-grid two">
          <section class="portal-card"><h2>Neues Angebot</h2><form class="portal-form" data-form="offer">
              <label>Name<input name="name" maxlength="80" required></label>
              <label>Kategorie<select name="category"><option value="insurance">Insurance</option><option value="sponsoring">Sponsoring</option><option value="hq">HQ</option><option value="marketplace">Marketplace</option></select></label>
            <label>Preis in EUR<input name="amount" type="number" min="0.01" step="0.01" required></label>
            <label class="full">Kurzbeschreibung<textarea name="description" maxlength="300" required></textarea></label>
            <label class="full">Konditionen<textarea name="terms" maxlength="2000" required></textarea></label>
            <label class="full">Ziel-URL (optional)<input name="url" type="url" placeholder="https://…"></label>
            <label class="full">Bild aus der Galerie<select name="gallery"><option value="${GALLERY_IMAGE}">Rennsport-Motiv · Website-Galerie</option><option value="upload">Eigenes Bild vom Gerät auswählen …</option></select></label>
            <label class="full">Eigenes Bild (optional)<input name="imageFile" type="file" accept="image/*"><small class="portal-muted">Auswahl aus der Gerätegalerie · maximal 600 KB.</small></label>
            <div class="portal-actions"><button class="portal-button primary">Angebot veröffentlichen</button></div>
          </form></section>
          <section class="portal-card"><h2>Veröffentlichte Angebote</h2>${data.offers.length?`<div class="portal-item-list">${data.offers.map(offer=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(offer.name)}</strong><small>${categoryName(offer.category)} · ${money(offer.amount)} · ${escapeHtml(offer.description)}</small><small>${escapeHtml(offer.terms||'')}</small></div><button class="portal-button danger" data-delete-offer="${offer.id}">Entfernen</button></div>`).join('')}</div>`:'<div class="portal-empty">Noch keine Angebote angelegt.</div>'}</section>
        </div>`;
    } else if (tab==='orders') {
      content = `${heading('Eingang','Sponsoren-Akten','Kaufanfragen aus dem Sponsorenbereich prüfen und weiterbearbeiten.')}
        <section class="portal-card"><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Angebot / Kontakt</th><th>Team</th><th>Datum</th><th>Status</th><th>Aktion</th></tr></thead><tbody>
        ${data.orders.length?data.orders.slice().reverse().map(order=>`<tr><td><strong>${escapeHtml(order.offerName)}</strong><br><span class="portal-muted">${categoryName(order.category)} · ${escapeHtml(order.contactName)} · ${escapeHtml(order.email)}</span><br>${escapeHtml(order.company||'')} ${money(order.amount)}<br>${escapeHtml(order.billingAddress||'')}<br><span class="portal-muted">Konditionen: ${escapeHtml(order.terms||'')}<br>${escapeHtml(order.notes||'')}</span></td><td>${escapeHtml(teamName(order.teamId))}</td><td>${date(order.createdAt)}</td><td>${statusBadge(order.status)}</td><td><div class="portal-actions">${order.status==='pending'?`<button class="portal-button primary" data-approve-order="${order.id}">Prüfen & Rechnung</button>`:''}</div></td></tr>`).join(''):'<tr><td colspan="5" class="portal-empty">Noch keine Anfragen vorhanden.</td></tr>'}
        </tbody></table></div></section>`;
    } else if (tab==='finance') {
      content = `${heading('Teamkonten','Rechnungen & Buchungen','Rechnungen hier erstellen; Teamchefs sehen sie im Teamkonto.')}
        <div class="portal-grid two"><section class="portal-card"><h2>Rechnung erstellen</h2><form class="portal-form" data-form="invoice">
          <label>Team${teamSelect()}</label><label>Betrag in EUR<input name="amount" type="number" min="0.01" step="0.01" required></label>
          <label class="full">Beschreibung<input name="description" maxlength="120" required></label>
          <label>Rechnung an<input name="billToName" maxlength="120"></label><label>Rechnungs-E-Mail<input name="billToEmail" type="email" maxlength="254"></label>
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
        <section class="portal-card" style="margin-top:15px"><h2>Rechnungsjournal</h2><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Rechnung</th><th>Team</th><th>Fällig</th><th>Betrag</th><th>Status</th><th>Aktion</th></tr></thead><tbody>${data.invoices.length?data.invoices.slice().reverse().map(invoice=>`<tr><td>${escapeHtml(invoice.number)}<br>${escapeHtml(invoice.description)}</td><td>${escapeHtml(teamName(invoice.teamId))}</td><td>${date(invoice.dueDate)}</td><td>${money(invoice.amount)}</td><td>${statusBadge(invoice.status)}</td><td><div class="portal-actions"><button class="portal-button" data-print-invoice="${invoice.id}">PDF</button>${invoice.status==='payment_requested'?`<button class="portal-button primary" data-confirm-payment="${invoice.id}">Zahlung bestätigen</button>`:''}</div></td></tr>`).join(''):'<tr><td colspan="6" class="portal-empty">Noch keine Rechnungen.</td></tr>'}</tbody></table></div></section>
        <section class="portal-card" style="margin-top:15px"><h2>Kontostände & Teamzugang</h2><div class="portal-grid">${teams.map(team=>`<article class="portal-card"><div class="portal-item"><span class="portal-team-mark" style="--team-color:${team.color}">${team.mark}</span><strong>${team.name}</strong></div><div class="portal-stat">${money(balance(team.id))}</div><a class="portal-button" href="../team/index.html?team=${team.id}">Team-E-Banking öffnen ↗</a></article>`).join('')}</div></section>`;
    } else if (tab==='contracts') {
      content = `${heading('Dokumentenverwaltung','Verträge','Vertragsentwürfe für Sponsoring, Versicherung, HQ und Fahrzeuge dem Team zur Prüfung vorlegen.')}
        <div class="portal-grid two"><section class="portal-card"><h2>Vertragsentwurf anlegen</h2><form class="portal-form" data-form="contract">
          <label>Team${teamSelect()}</label><label>Vertragsart<select name="type"><option>Sponsoring</option><option>Versicherung</option><option>HQ</option><option>Fahrzeug</option></select></label>
          <label class="full">Titel<input name="title" maxlength="100" required></label>
          <label class="full">Konditionen / Zusammenfassung<textarea name="terms" maxlength="1500" required></textarea></label>
          <label>Gültig bis<input name="endDate" type="date" required></label><div class="portal-actions"><button class="portal-button primary">Zur Prüfung senden</button></div>
        </form></section><section class="portal-card"><h2>Hinweis</h2><p>Die Annahme im Demo-Portal ist keine rechtsverbindliche elektronische Signatur. Vor echten Vereinbarungen sind Backend, Identitätsprüfung und rechtliche Dokumente erforderlich.</p></section></div>
        <section class="portal-card" style="margin-top:15px"><h2>Vertragsübersicht</h2><div class="portal-item-list">${data.contracts.length?data.contracts.slice().reverse().map(contract=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(contract.title)}</strong><small>${escapeHtml(contract.type)} · ${escapeHtml(teamName(contract.teamId))} · gültig bis ${date(contract.endDate)}</small></div>${statusBadge(contract.status)}</div>`).join(''):'<div class="portal-empty">Noch keine Verträge erfasst.</div>'}</div></section>`;
    } else if (tab==='accounts') {
      content = `${heading('Zugriffsverwaltung','Benutzer & Rollen','Neue Admin- und Teamchef-Zugänge anlegen. Teamchefs erhalten Zugriff ausschließlich auf das ausgewählte Team.')}
        <section class="portal-card"><form class="portal-form" data-form="account">
          <label>Name<input name="displayName" maxlength="80" required></label>
          <label>E-Mail-Adresse<input name="email" type="email" maxlength="254" autocomplete="off" required></label>
          <label>Passwort<input name="password" type="password" minlength="12" maxlength="128" autocomplete="new-password" required><small class="portal-muted">Mindestens 12 Zeichen. Das Passwort wird nicht in der Website gespeichert.</small></label>
          <label>Rolle<select name="role"><option value="team_chief">Teamchef</option><option value="admin">Admin</option></select></label>
          <label class="full" data-account-team-field>Team${teamSelect()}</label>
          <div class="portal-actions"><button class="portal-button primary">Konto anlegen</button></div>
        </form></section>
        <div class="portal-warning">Konten werden über Supabase Auth angelegt. Die Supabase-Konfiguration und die Edge Function müssen vor der Nutzung eingerichtet sein.</div>`;
    } else {
      content = `${heading('Support & Betrieb','Probleme und Meldungen','Alle eingereichten Team-Anliegen zentral ansehen und ihren Bearbeitungsstand aktualisieren.')}
        <section class="portal-card"><div class="portal-table-wrap"><table class="portal-table"><thead><tr><th>Meldung</th><th>Team</th><th>Erstellt</th><th>Status</th><th>Aktion</th></tr></thead><tbody>
        ${data.tickets.length?data.tickets.slice().reverse().map(ticket=>`<tr><td><strong>${escapeHtml(ticket.subject)}</strong><br><span class="portal-muted">${escapeHtml(ticket.category)} · ${escapeHtml(ticket.details)}</span></td><td>${escapeHtml(teamName(ticket.teamId))}</td><td>${date(ticket.createdAt)}</td><td>${statusBadge(ticket.status)}</td><td><div class="portal-actions">${ticket.status!=='in_progress'?`<button class="portal-button" data-ticket-status="${ticket.id}" data-next-status="in_progress">In Bearbeitung</button>`:''}${ticket.status!=='resolved'?`<button class="portal-button primary" data-ticket-status="${ticket.id}" data-next-status="resolved">Erledigen</button>`:''}</div></td></tr>`).join(''):'<tr><td colspan="5" class="portal-empty">Keine offenen Meldungen vorhanden.</td></tr>'}
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
        <div class="portal-grid"><article class="portal-card portal-balance"><div class="portal-label-text">Verfügbarer Kontostand</div><div class="portal-stat">${money(balance(selected.id))}</div><div class="portal-label-text">Demo-Buchungen in EUR</div></article><article class="portal-card"><div class="portal-label-text">Offene Rechnungen</div><div class="portal-stat">${invoices.filter(invoice=>invoice.status!=='paid').length}</div><div class="portal-label-text">Fällig oder in Bearbeitung</div></article><article class="portal-card"><div class="portal-label-text">Verträge</div><div class="portal-stat">${contracts.length}</div><div class="portal-label-text">Entwürfe und Vereinbarungen</div></article><article class="portal-card"><div class="portal-label-text">Team-Logo</div><div class="portal-item">${data.teamLogos[selected.id]?`<img class="portal-team-mark" style="object-fit:contain;background:transparent" src="${escapeHtml(data.teamLogos[selected.id])}" alt="${escapeHtml(selected.name)}-Logo">`:`<span class="portal-team-mark" style="--team-color:${selected.color}">${selected.mark}</span>`}<strong>${escapeHtml(selected.name)}</strong></div><div class="portal-label-text">${data.teamLogos[selected.id]?'Hochgeladenes Team-Logo':'Platzhalter bis zum Logo-Upload im Admin Center'}</div></article></div>
        <div class="portal-grid two" style="margin-top:15px"><section class="portal-card" id="rechnungen"><h2>Rechnungen</h2><div class="portal-item-list">${invoices.length?invoices.slice().reverse().map(invoice=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(invoice.number)} · ${escapeHtml(invoice.description)}</strong><small>${money(invoice.amount)} · fällig ${date(invoice.dueDate)}</small></div><div class="portal-actions">${statusBadge(invoice.status)}<button class="portal-button" data-print-invoice="${invoice.id}">PDF / Drucken</button>${invoice.status==='open'?`<button class="portal-button primary" data-request-payment="${invoice.id}">Zahlung vormerken</button>`:''}</div></div>`).join(''):'<div class="portal-empty">Keine Rechnungen vorhanden.</div>'}</div></section>
        <section class="portal-card" id="vertraege"><h2>Verträge</h2><div class="portal-item-list">${contracts.length?contracts.slice().reverse().map(contract=>`<div class="portal-item"><div class="portal-item-copy"><strong>${escapeHtml(contract.title)}</strong><small>${escapeHtml(contract.type)} · gültig bis ${date(contract.endDate)}<br>${escapeHtml(contract.terms)}</small></div><div class="portal-actions">${statusBadge(contract.status)}${contract.status==='pending'?`<button class="portal-button primary" data-sign-contract="${contract.id}">Annehmen</button><button class="portal-button" data-decline-contract="${contract.id}">Ablehnen</button>`:''}</div></div>`).join(''):'<div class="portal-empty">Keine Vertragsentwürfe vorhanden.</div>'}</div></section></div>
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
      ${offer.image?`<img src="${escapeHtml(offer.image)}" alt="">`:''}<div class="portal-kicker">${categoryName(offer.category)}</div><h2>${escapeHtml(offer.name)}</h2>
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

  async function handleForm(form) {
    const fields = Object.fromEntries(new FormData(form));
    if (form.dataset.form==='home') {
      data.home.title = fields.title.trim();
      data.home.claim = fields.claim.trim();
      data.home.intro = fields.intro.trim();
      data.home.image = form.querySelector('[name="imageFile"]').dataset.image || (fields.gallery==='upload'?data.home.image:fields.gallery);
      if (save()) { applyHome(); showToast('Startseite gespeichert.'); }
    } else if (form.dataset.form==='team-logo') {
      const fileInput=form.querySelector('[name="imageFile"]');
      const image=fileInput.dataset.image;
      if(!image) throw new Error('Bitte zuerst ein Teamlogo aus der Gerätegalerie auswählen.');
      data.teamLogos[fields.teamId]=image;
      if(save()){renderAdminTab('content');showToast(`Teamlogo für ${teamName(fields.teamId)} gespeichert.`);}
    } else if (form.dataset.form==='offer') {
      if (fields.url && !safeUrl(fields.url)) throw new Error('Bitte eine gültige http(s)-URL eingeben.');
      const amount = cents(fields.amount);
      const image = form.querySelector('[name="imageFile"]').dataset.image || (fields.gallery==='upload'?'':fields.gallery);
      if (window.zfcSupabase) {
        const {data: row, error} = await window.zfcSupabase.from('sponsor_offers').insert({
          category:fields.category,name:fields.name.trim(),description:fields.description.trim(),terms:fields.terms.trim(),target_url:fields.url.trim()||null,
          amount_cents:amount,image_path:image.startsWith('https://')?image:null,published:true,created_by:window.zfcProfile.id
        }).select('*').single();
        if (error) throw new Error('Angebot konnte nicht veröffentlicht werden.');
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
        if (error) throw new Error('Rechnung konnte nicht erstellt werden.');
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
      data.contracts.push({id:uid(),teamId:fields.teamId,type:fields.type,title:fields.title.trim(),terms:fields.terms.trim(),endDate:fields.endDate,status:'pending',createdAt:new Date().toISOString()});
      if (save()) { renderAdminTab('contracts'); showToast('Vertrag zur Prüfung gesendet.'); }
    } else if (form.dataset.form==='support-ticket') {
      data.tickets.push({id:uid(),teamId:fields.teamId,category:fields.category,subject:fields.subject.trim(),details:fields.details.trim(),status:'open',createdAt:new Date().toISOString()});
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
    } else if (form.dataset.form==='account') {
      if (!window.zfcSupabase || window.zfcProfile?.role!=='admin') throw new Error('Für die Kontoanlage ist eine angemeldete Admin-Sitzung erforderlich.');
      const { error } = await window.zfcSupabase.functions.invoke('admin-create-user', {body:{email:fields.email.trim(),password:fields.password,displayName:fields.displayName.trim(),role:fields.role,teamId:fields.role==='team_chief'?fields.teamId:null}});
      if (error) throw new Error('Konto konnte nicht angelegt werden. Prüfe E-Mail, Passwort und Supabase-Funktionen.');
      form.reset(); renderAdminTab('accounts'); showToast('Benutzerkonto wurde angelegt.');
    }
  }

  function invoicePrint(invoice) {
    const team = teams.find(entry=>entry.id===invoice.teamId);
    const printWindow = window.open('', '_blank', 'width=800,height=950');
    if (!printWindow) { showToast('Druckfenster blockiert. Bitte Pop-ups für diese Seite erlauben.',true); return; }
    const recipient = [invoice.billToCompany,invoice.billToName,invoice.billToEmail,invoice.billToAddress]
      .filter(Boolean).map(value=>escapeHtml(value).replace(/\n/g,'<br>')).join('<br>') || escapeHtml(team.name);
    printWindow.document.write(`<!doctype html><html lang="de"><meta charset="utf-8"><title>Rechnungsentwurf ${escapeHtml(invoice.number)}</title><style>body{font:15px Arial,sans-serif;color:#17191c;max-width:760px;margin:60px auto;padding:0 35px}header{display:flex;justify-content:space-between;gap:30px;border-bottom:2px solid #222;padding-bottom:22px}h1{font-size:32px}table{width:100%;border-collapse:collapse;margin-top:34px}td{padding:14px;border-bottom:1px solid #ddd}.total{font-size:22px;font-weight:bold;text-align:right;margin-top:28px}.muted{color:#666;font-size:12px;margin-top:50px}@media print{button{display:none}}</style><header><div><strong>ZFC · ZENITH FORMULA CHAMPIONSHIP</strong><p>Rechnungsentwurf · ${escapeHtml(invoice.number)}</p></div><div><small>Rechnung an</small><br>${recipient}</div></header><h1>Rechnungsentwurf</h1><p>Rechnungsnummer: ${escapeHtml(invoice.number)}<br>Rechnungsdatum: ${date(invoice.createdAt)}<br>Fällig am: ${date(invoice.dueDate)}<br>Referenz: ${escapeHtml(invoice.reference||'—')}</p><table><tr><td>${escapeHtml(invoice.description)}</td><td style="text-align:right">${money(invoice.amount)}</td></tr></table><p class="total">Gesamtbetrag: ${money(invoice.amount)}</p><p class="muted">Entwurf zur Prüfung. Ergänze vor Versand die vollständigen Angaben des Rechnungsausstellers und prüfe die geltenden Rechnungsanforderungen. Zahlung und Überweisung erfolgen außerhalb dieses Portals.</p><button onclick="window.print()">PDF speichern / Drucken</button><script>window.onload=()=>window.print()<\/script></html>`);
    printWindow.document.close();
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
    return {id:row.id,category:row.category||'sponsoring',name:row.name,description:row.description,terms:row.terms||'',url:row.target_url||'',amount:Number(row.amount_cents),image:row.image_path||'',createdAt:row.created_at};
  }

  function mapOrder(row) {
    return {id:row.id,offerId:row.offer_id,offerName:row.offer_name,category:row.category||'sponsoring',terms:row.offer_terms||'',amount:Number(row.amount_cents),teamId:row.team_id,contactName:row.contact_name,email:row.email,company:row.company||'',billingAddress:row.billing_address||'',notes:row.customer_notes||'',status:row.status,createdAt:row.created_at};
  }

  function mapInvoice(row) {
    return {id:row.id,number:row.invoice_number,teamId:row.team_id,amount:Number(row.amount_cents),description:row.description,dueDate:row.due_date,reference:row.reference||'',orderId:row.order_id,billToName:row.bill_to_name||'',billToEmail:row.bill_to_email||'',billToCompany:row.bill_to_company||'',billToAddress:row.bill_to_address||'',status:row.status,createdAt:row.created_at};
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
    const offersQuery = window.zfcSupabase.from('sponsor_offers').select('*').eq('published',true);
    const {data: offerRows, error: offerError} = await offersQuery.order('created_at', {ascending:false});
    if (offerError) throw offerError;
    data.offers = offerRows.map(mapOffer);
    if (page === 'admin') {
      const [{data: orderRows, error: orderError}, {data: invoiceRows, error: invoiceError}] = await Promise.all([
        window.zfcSupabase.from('sponsor_orders').select('*').order('created_at', {ascending:false}),
        window.zfcSupabase.from('invoices').select('*').order('created_at', {ascending:false})
      ]);
      if (orderError) throw orderError;
      if (invoiceError) throw invoiceError;
      data.orders = orderRows.map(mapOrder);
      data.invoices = invoiceRows.map(mapInvoice);
    } else if (page === 'team') {
      const {data: invoiceRows, error} = await window.zfcSupabase.from('invoices').select('*').eq('team_id', selectedTeamId).order('created_at', {ascending:false});
      if (error) throw error;
      data.invoices = invoiceRows.map(mapInvoice);
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
    renderPublicOffers();
    if (page==='admin') renderAdminTab();
    if (page==='team') renderTeam(window.zfcProfile?.team_id || new URLSearchParams(location.search).get('team') || teams[0].id);
  }

  document.addEventListener('click', async event => {
    const button = event.target.closest('[data-admin-tab]');
    if (button && $('#portal-root')) { renderAdminTab(button.dataset.adminTab); return; }
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
          const {error} = await window.zfcSupabase.from('sponsor_offers').update({published:false}).eq('id',removeOffer.dataset.deleteOffer);
          if (error) throw error;
        }
        data.offers=data.offers.filter(item=>item.id!==removeOffer.dataset.deleteOffer);
        if(save())renderAdminTab('offers');
      } catch { showToast('Angebot konnte nicht entfernt werden.',true); }
      return;
    }
    const ticketButton = event.target.closest('[data-ticket-status]');
    if (ticketButton) { const ticket=data.tickets.find(item=>item.id===ticketButton.dataset.ticketStatus);if(ticket){ticket.status=ticketButton.dataset.nextStatus;if(save()){renderAdminTab('tickets');showToast('Meldungsstatus aktualisiert.');}}return; }
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
    if (contract) { const item=data.contracts.find(entry=>entry.id===(contract.dataset.signContract||contract.dataset.declineContract));if(item?.status==='pending'){item.status=contract.dataset.signContract?'signed':'declined';if(save()){renderTeam(currentTeamId);showToast(item.status==='signed'?'Annahme im Demo-Portal vorgemerkt.':'Vertrag abgelehnt.');}}return; }
    const print = event.target.closest('[data-print-invoice]');
    if (print) { const invoice=data.invoices.find(item=>item.id===print.dataset.printInvoice);if(invoice)invoicePrint(invoice); }
  });

  document.addEventListener('change', event => {
    if (event.target.matches('[data-team-picker]')) { renderTeam(event.target.value); return; }
    if (event.target.matches('[name="role"]')) {
      const teamField = $('[data-account-team-field]');
      if (teamField) {
        teamField.hidden = event.target.value==='admin';
        const teamControl = teamField.querySelector('[name="teamId"]');
        if (teamControl) teamControl.required = event.target.value==='team_chief';
      }
      return;
    }
    if (event.target.matches('[name="gallery"]')) {
      const form=event.target.form, file=form.querySelector('[name="imageFile"]');
      if(event.target.value!=='upload'){file.dataset.image='';const preview=form.querySelector('[data-home-preview]');if(preview)preview.src=event.target.value;}
    }
    if (event.target.matches('[name="imageFile"]') && event.target.files[0]) {
      const file=event.target.files[0], form=event.target.form;
      if(!file.type.startsWith('image/')){showToast('Bitte eine Bilddatei auswählen.',true);event.target.value='';return;}
      if(file.size>600*1024){showToast('Das Bild ist zu groß. Bitte eine Datei bis 600 KB wählen.',true);event.target.value='';return;}
      const reader=new FileReader();
      reader.onload=()=>{event.target.dataset.image=reader.result;const preview=form.querySelector('[data-home-preview]');if(preview)preview.src=reader.result;};
      reader.onerror=()=>showToast('Bild konnte nicht gelesen werden.',true);
      reader.readAsDataURL(file);
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
