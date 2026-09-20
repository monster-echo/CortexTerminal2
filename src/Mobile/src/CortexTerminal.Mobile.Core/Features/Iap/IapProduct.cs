namespace CortexTerminal.Mobile.Core.Features.Iap;

/// <summary>
/// A displayable in-app purchase product fetched from the platform store.
/// </summary>
public sealed record IapProduct(
    string ProductId,
    string Title,
    string Description,
    string LocalizedPrice,
    string CurrencyCode);
