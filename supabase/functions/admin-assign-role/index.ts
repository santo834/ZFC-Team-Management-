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
    const { data: callerProfile, error: profileError } = await service
      .from("profiles").select("role").eq("id", callerData.user.id).single();
    if (profileError || callerProfile?.role !== "admin") return response(403, { error: "Nur Admins können Rollen ändern." });

    const { profileId, role, teamId } = await request.json();
    if (typeof profileId !== "string" ||
        !["admin", "team_chief"].includes(role) ||
        (role === "team_chief" && typeof teamId !== "string") ||
        (role === "admin" && teamId !== null)) {
      return response(400, { error: "Bitte prüfe Rolle und Teamzuweisung." });
    }

    if (role === "team_chief") {
      const { data: team, error: teamError } = await service
        .from("teams").select("id").eq("id", teamId).maybeSingle();
      if (teamError || !team) return response(400, { error: "Das ausgewählte Team wurde nicht gefunden." });
    }

    const { data: updatedProfile, error: updateError } = await service
      .from("profiles")
      .update({ role, team_id: role === "team_chief" ? teamId : null })
      .eq("id", profileId)
      .select("id, email, display_name, role, team_id")
      .single();
    if (updateError) return response(400, { error: "Rolle konnte nicht gespeichert werden." });

    return response(200, { profile: updatedProfile });
  } catch {
    return response(500, { error: "Rolle konnte nicht gespeichert werden." });
  }
});
