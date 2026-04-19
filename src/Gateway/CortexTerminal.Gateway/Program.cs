using CortexTerminal.Contracts;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => Results.Ok(new ServiceIdentity("CortexTerminal.Gateway")));

app.Run();
