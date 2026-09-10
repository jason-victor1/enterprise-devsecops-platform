using System.Text;
using System.Text.Json;

if (args.Contains("--health"))
{
    using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
    try
    {
        var response = await client.GetAsync("http://127.0.0.1:8082/healthz");
        Environment.Exit(response.IsSuccessStatusCode ? 0 : 1);
    }
    catch
    {
        Environment.Exit(1);
    }
}

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(8082);
});

builder.Services.AddHttpClient("CatalogClient", client =>
{
    client.BaseAddress = new Uri(Environment.GetEnvironmentVariable("CATALOG_SERVICE_URL") ?? "http://catalog:8080");
    client.Timeout = TimeSpan.FromSeconds(5);
});

builder.Services.AddHttpClient("InventoryClient", client =>
{
    client.BaseAddress = new Uri(Environment.GetEnvironmentVariable("INVENTORY_SERVICE_URL") ?? "http://inventory:8081");
    client.Timeout = TimeSpan.FromSeconds(5);
});

builder.Services.AddHttpClient("PaymentClient", client =>
{
    client.BaseAddress = new Uri(Environment.GetEnvironmentVariable("PAYMENT_SERVICE_URL") ?? "http://payment:8083");
    client.Timeout = TimeSpan.FromSeconds(5);
});

var app = builder.Build();

app.MapGet("/healthz", () => Results.Ok(new { status = "healthy", service = "orders" }));

app.MapPost("/orders", async (
    JsonElement orderRequest,
    IHttpClientFactory clientFactory) =>
{
    if (!orderRequest.TryGetProperty("itemId", out var itemIdProp) ||
        !orderRequest.TryGetProperty("quantity", out var qtyProp) ||
        !orderRequest.TryGetProperty("amount", out var amountProp))
    {
        return Results.BadRequest(new { error = "Missing required fields: itemId, quantity, amount" });
    }

    var itemId = itemIdProp.GetString();
    var quantity = qtyProp.GetInt32();
    var amount = amountProp.GetDecimal();

    var catalogClient = clientFactory.CreateClient("CatalogClient");
    var catResp = await catalogClient.GetAsync($"/items/{itemId}");
    if (!catResp.IsSuccessStatusCode)
    {
        return Results.NotFound(new { error = "Item unavailable or not found in catalog", itemId });
    }

    var inventoryClient = clientFactory.CreateClient("InventoryClient");
    var deductPayload = new StringContent(
        JsonSerializer.Serialize(new { itemId, quantity }),
        Encoding.UTF8,
        "application/json"
    );
    var invResp = await inventoryClient.PostAsync("/deduct", deductPayload);
    if (!invResp.IsSuccessStatusCode)
    {
        return Results.Conflict(new { error = "Inventory reservation failed" });
    }

    var paymentClient = clientFactory.CreateClient("PaymentClient");
    var payPayload = new StringContent(
        JsonSerializer.Serialize(new { orderId = Guid.NewGuid().ToString(), amount }),
        Encoding.UTF8,
        "application/json"
    );
    var payResp = await paymentClient.PostAsync("/process", payPayload);
    if (!payResp.IsSuccessStatusCode)
    {
        return Results.Json(new { error = "Payment gateway rejected transaction" }, statusCode: 502);
    }

    return Results.Ok(new
    {
        orderId = Guid.NewGuid().ToString(),
        status = "confirmed",
        itemId,
        quantity,
        totalAmount = amount
    });
});

app.Run();
