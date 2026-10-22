(() => {
  const config = window.ZFC_SUPABASE_CONFIG || {};
  let client = null;
  let clientError = '';
  window.zfcProfile = null;

  async function initializeClient() {
    if (!config.url || !config.anonKey) {
      clientError = 'Supabase-URL oder Publishable-Key fehlt in der Client-Konfiguration.';
      return null;
    }

    let createClient = window.supabase?.createClient;
    if (!createClient) {
      await new Promise(resolve => {
        const script = document.createElement('script');
        script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/dist/umd/supabase.js';
        script.onload = resolve;
        script.onerror = resolve;
        document.head.append(script);
      });
      createClient = window.supabase?.createClient;
    }

    if (!createClient) {
      try {
        const supabaseModule = await import('https://esm.sh/@supabase/supabase-js@2');
        createClient = supabaseModule.createClient;
      } catch {
        clientError = 'Die Supabase-Bibliothek konnte nicht geladen werden. Prüfe die Internetverbindung oder CDN-Freigabe.';
        return null;
      }
    }

    try {
      client = createClient(config.url, config.anonKey);
      window.zfcSupabase = client;
      return client;
    } catch {
      clientError = 'Der Supabase-Client konnte mit der Projekt-URL und dem Publishable-Key nicht gestartet werden.';
      return null;
    }
  }

  window.zfcSupabase = null;
  const clientReady = initializeClient();
  window.zfcSupabaseReady = clientReady;

  function showPortalError(root, message) {
    const main = document.createElement('main');
    const warning = document.createElement('div');
    main.className = 'portal-main';
    warning.className = 'portal-warning';
    warning.textContent = message;
    main.append(warning);
    root.replaceChildren(main);
  }

  async function readProfile(userId) {
    const { data, error } = await client.from('profiles').select('id,display_name,role,team_id').eq('id', userId).single();
    if (error) throw error;
    return data;
  }

  async function authorizePortal() {
    const root = document.querySelector('#portal-root');
    const activeClient = await clientReady;
    if (!root) return { configured: Boolean(activeClient), profile: null };
    if (!activeClient) {
      showPortalError(root, clientError || 'Supabase-Client ist nicht verfügbar.');
      return null;
    }
    const { data: { session } } = await client.auth.getSession();
    if (!session) {
      location.replace('../login/index.html');
      return null;
    }
    try {
      const profile = await readProfile(session.user.id);
      const page = root.dataset.portalPage;
      if ((page === 'admin' && profile.role !== 'admin') || (page === 'team' && !['admin', 'team_chief'].includes(profile.role))) {
        location.replace(profile.role === 'admin' ? '../admin/index.html' : '../team/index.html');
        return null;
      }
      if (page === 'team' && profile.role === 'team_chief' && !profile.team_id) throw new Error('Deinem Teamchef-Konto ist noch kein Team zugewiesen.');
      window.zfcProfile = profile;
      return { configured: true, profile };
    } catch (error) {
      showPortalError(root, String(error.message || 'Profil konnte nicht geladen werden.'));
      return null;
    }
  }

  window.zfcAuthorizePortal = authorizePortal;

  const requestedRole = new URLSearchParams(location.search).get('role');
  if (requestedRole === 'admin' || requestedRole === 'team_chief') {
    const roleLabel = requestedRole === 'admin' ? 'Admin' : 'Teamchef';
    const kicker = document.querySelector('[data-login-kicker]');
    const title = document.querySelector('[data-login-title]');
    const description = document.querySelector('[data-login-description]');
    if (kicker) kicker.textContent = `${roleLabel}-Login`;
    if (title) title.textContent = `Als ${roleLabel} anmelden`;
    if (description) description.textContent = 'Deine gespeicherte Rolle wird geprüft und öffnet den passenden Arbeitsbereich.';
  }

  document.addEventListener('click', async (event) => {
    if (!event.target.closest('[data-sign-out]')) return;
    const activeClient = await clientReady;
    if (activeClient) await activeClient.auth.signOut();
    location.assign('../login/index.html');
  });

  document.addEventListener('submit', async (event) => {
    const form = event.target.closest('[data-login-form]');
    if (!form) return;
    event.preventDefault();
    const message = form.querySelector('[data-login-message]');
    const submit = form.querySelector('button[type="submit"]');
    const activeClient = await clientReady;
    if (!activeClient) {
      message.textContent = clientError || 'Supabase-Client ist nicht verfügbar.';
      return;
    }
    submit.disabled = true;
    message.textContent = '';
    const fields = Object.fromEntries(new FormData(form));
    const { data, error } = await activeClient.auth.signInWithPassword({ email: fields.email, password: fields.password });
    if (error) {
      const errorMessage = String(error.message || 'Unbekannter Auth-Fehler.');
      if (/email not confirmed/i.test(errorMessage)) {
        message.textContent = 'Bitte bestätige zuerst die E-Mail-Adresse über den Link von Supabase.';
      } else if (/invalid login credentials/i.test(errorMessage)) {
        message.textContent = 'E-Mail oder Passwort stimmt nicht. Prüfe auch, ob das Auth-Konto bereits angelegt ist.';
      } else {
        message.textContent = `Supabase-Anmeldung fehlgeschlagen: ${errorMessage}`;
      }
      submit.disabled = false;
      return;
    }
    try {
      const profile = await readProfile(data.user.id);
      location.assign(profile.role === 'admin' ? '../admin/index.html' : '../team/index.html');
    } catch (profileError) {
      await client.auth.signOut();
      message.textContent = `Anmeldung erfolgreich, aber das Rollenprofil fehlt oder ist nicht lesbar: ${profileError.message || 'Profilfehler'}`;
      submit.disabled = false;
    }
  });
})();
