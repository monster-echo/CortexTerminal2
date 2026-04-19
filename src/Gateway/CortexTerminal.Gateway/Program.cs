var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => Results.Ok(new { Name = "CortexTerminal.Gateway" }));

app.Run();
