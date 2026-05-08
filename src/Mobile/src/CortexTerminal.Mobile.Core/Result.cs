namespace CortexTerminal.Mobile.Core;

public sealed record Result<T>(bool IsSuccess, T? Data = default, AppError? Error = null)
{
    public static Result<T> Success(T data) => new(true, data, null);
    public static Result<T> Failure(AppError error) => new(false, default, error);
}
