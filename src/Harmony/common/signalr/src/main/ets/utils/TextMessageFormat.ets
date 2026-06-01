const RECORD_SEPARATOR = '';

export class TextMessageFormat {
  static write(output: string): string {
    return output + RECORD_SEPARATOR;
  }

  static parse(input: string): string[] {
    if (input.length === 0) {
      return [];
    }
    const parts = input.split(RECORD_SEPARATOR);
    // Filter out trailing empty strings from trailing separator
    if (parts.length > 0 && parts[parts.length - 1].length === 0) {
      parts.splice(parts.length - 1, 1);
    }
    return parts;
  }
}
