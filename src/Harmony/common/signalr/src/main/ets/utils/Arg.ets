export function isRequired(value: Object | undefined | null, propertyName: string): void {
  if (value === undefined || value === null) {
    throw new Error(`Argument '${propertyName}' is required`);
  }
}

export function isNotEmptyString(value: string, propertyName: string): void {
  if (!value) {
    throw new Error(`Argument '${propertyName}' must be a non-empty string`);
  }
}
