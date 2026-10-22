import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return response(405, { error: "Method not allowed" });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = request.headers.get("Authorization");
    if (!url || !anonKey || !serviceKey || !authorization) return response(401, { error: "Anmeldung erforderlich." });

    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: callerData, error: callerError } = await callerClient.auth.getUser();
    if (callerError || !callerData.user) return response(401, { error: "Anmeldung erforderlich." });

    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: profile, error: profileError } = await service
      .from("profiles").select("role").eq("id", callerData.user.id).single();
    if (profileError || profile?.role !== "admin") return response(403, { error: "Nur Admins können Konten anlegen." });

    const { email, password, displayName, role, teamId } = await request.json();
    if (typeof email !== "string" || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        typeof password !== "string" || password.length < 12 || password.length > 128 ||
        typeof displayName !== "string" || displayName.trim().length < 1 || displayName.length > 80 ||
        !["admin", "team_chief"].includes(role) ||
        (role === "team_chief" && typeof teamId !== "string") ||
        (role === "admin" && teamId !== null)) {
      return response(400, { error: "Bitte prüfe E-Mail, Passwort, Rolle und Team." });
    }

    const { data: created, error: createError } = await service.auth.admin.createUser({
      email: email.trim().toLowerCase(),
      password,
      email_confirm: true,
      user_metadata: { display_name: displayName.trim() },
    });
    if (createError || !created.user) return response(400, { error: "Konto konnte nicht angelegt werden. Prüfe, ob die E-Mail bereits verwendet wird." });

    const { error: assignmentError } = await service.from("profiles").update({
      display_name: displayName.trim(),
      role,
      team_id: role === "team_chief" ? teamId : null,
    }).eq("id", created.user.id);
    if (assignmentError) {
      await service.auth.admin.deleteUser(created.user.id);
      return response(500, { error: "Rollenzuweisung fehlgeschlagen; das neue Konto wurde entfernt." });
    }

    return response(201, { id: created.user.id, email: created.user.email });
  } catch {
    return response(500, { error: "Konto konnte nicht angelegt werden." });
  }
});
