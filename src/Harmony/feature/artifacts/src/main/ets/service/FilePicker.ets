/**
 * @file FilePicker.ets
 * @brief Wraps @ohos.file.picker.DocumentViewPicker for selecting a single file.
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
  static async selectSingle(): Promise<FilePickerResult | null> {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 1
    const viewer = new picker.DocumentViewPicker()
    const uris = await viewer.select(options)
    if (uris.length === 0) {
      return null
    }
    const uri = uris[0]
    const filename = FilePicker.extractFilename(uri)
    return new FilePickerResult(uri, filename)
  }

  static extractFilename(uri: string): string {
    const slashIdx = uri.lastIndexOf('/')
    if (slashIdx < 0) {
      return uri
    }
    return uri.substring(slashIdx + 1)
  }
}
