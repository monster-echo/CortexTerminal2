/**
 * @file FilePicker.ets
 * @brief Wraps @ohos.file.picker.DocumentViewPicker for selecting multiple files.
 */
import picker from '@ohos.file.picker'

export class FilePickerResult {
  uri: string = ''
  filename: string = ''

  constructor(uri: string, filename: string) {
    this.uri = uri
    this.filename = filename
  }
}

export class FilePicker {
  static async selectMultiple(maxSelectNumber: number): Promise<FilePickerResult[]> {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = maxSelectNumber
    const viewer = new picker.DocumentViewPicker()
    const uris = await viewer.select(options)
    const results: FilePickerResult[] = []
    for (let i = 0; i < uris.length; i++) {
      results.push(new FilePickerResult(uris[i], FilePicker.extractFilename(uris[i])))
    }
    return results
  }

  static extractFilename(uri: string): string {
    const slashIdx = uri.lastIndexOf('/')
    if (slashIdx < 0) {
      return uri
    }
    return uri.substring(slashIdx + 1)
  }
}
