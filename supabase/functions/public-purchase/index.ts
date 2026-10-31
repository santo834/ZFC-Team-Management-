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
    const { offerId, teamId, contactName, email, company, billingAddress, notes } = await request.json();
    if (typeof offerId !== "string" || typeof teamId !== "string" ||
        typeof contactName !== "string" || contactName.trim().length < 1 || contactName.length > 80 ||
        typeof email !== "string" || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        typeof company !== "string" || company.length > 120 ||
        typeof billingAddress !== "string" || billingAddress.length > 300 ||
        typeof notes !== "string" || notes.length > 1000) {
      return response(400, { error: "Bitte prüfe die Anfrageangaben." });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return response(500, { error: "Marketplace ist nicht vollständig konfiguriert." });

    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    const { count, error: rateError } = await service
      .from("sponsor_orders")
      .select("id", { count: "exact", head: true })
      .eq("email", email.trim().toLowerCase())
      .gte("created_at", since);
    if (rateError) throw rateError;
    if ((count || 0) >= 5) return response(429, { error: "Zu viele Anfragen. Bitte später erneut versuchen." });

    const { data: offer, error: offerError } = await service
      .from("sponsor_offers")
      .select("id, name, amount_cents, category, terms, published")
      .eq("id", offerId)
      .eq("published", true)
      .single();
    if (offerError || !offer) return response(404, { error: "Dieses Angebot ist nicht mehr verfügbar." });

    const { data, error } = await service.from("sponsor_orders").insert({
      offer_id: offer.id,
      team_id: teamId,
      offer_name: offer.name,
      amount_cents: offer.amount_cents,
      category: offer.category,
      offer_terms: offer.terms || "",
      contact_name: contactName.trim(),
      email: email.trim().toLowerCase(),
      company: company.trim(),
      billing_address: billingAddress.trim(),
      customer_notes: notes.trim(),
      status: "pending",
    }).select("id").single();
    if (error) throw error;
    return response(201, { id: data.id });
  } catch {
    return response(500, { error: "Die Anfrage konnte nicht gespeichert werden." });
  }
});
