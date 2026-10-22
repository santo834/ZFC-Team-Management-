(() => {
  const config = window.ZFC_SUPABASE_CONFIG || {};
  const client = config.url && config.anonKey && window.supabase
    ? window.supabase.createClient(config.url, config.anonKey)
    : null;
  window.zfcSupabase = client;
  window.zfcProfile = null;

  async function readProfile(userId) {
    const { data, error } = await client.from('profiles').select('id,display_name,role,team_id').eq('id', userId).single();
    if (error) throw error;
    return data;
  }

  async function authorizePortal() {
    const root = document.querySelector('#portal-root');
    if (!client || !root) return { configured: Boolean(client), profile: null };
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
      const main = document.createElement('main');
      const warning = document.createElement('div');
      main.className = 'portal-main';
      warning.className = 'portal-warning';
      warning.textContent = String(error.message || 'Profil konnte nicht geladen werden.');
      main.append(warning);
      root.replaceChildren(main);
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
    if (client) await client.auth.signOut();
    location.assign('../login/index.html');
  });

  document.addEventListener('submit', async (event) => {
    const form = event.target.closest('[data-login-form]');
    if (!form) return;
    event.preventDefault();
    const message = form.querySelector('[data-login-message]');
    const submit = form.querySelector('button[type="submit"]');
    if (!client) {
      message.textContent = 'Supabase ist noch nicht konfiguriert. Bitte URL und öffentlichen Schlüssel hinterlegen.';
      return;
    }
    submit.disabled = true;
    message.textContent = '';
    const fields = Object.fromEntries(new FormData(form));
    const { data, error } = await client.auth.signInWithPassword({ email: fields.email, password: fields.password });
    if (error) {
      message.textContent = 'Anmeldung fehlgeschlagen. Prüfe E-Mail und Passwort.';
      submit.disabled = false;
      return;
    }
    try {
      const profile = await readProfile(data.user.id);
      location.assign(profile.role === 'admin' ? '../admin/index.html' : '../team/index.html');
    } catch {
      await client.auth.signOut();
      message.textContent = 'Für dieses Konto wurde kein gültiges Rollenprofil gefunden.';
      submit.disabled = false;
    }
  });
})();
