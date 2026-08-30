/**
 * @file FileModels.ets
 * @brief View models for the remote file browser.
 *
 * The Gateway returns FileListing JSON ({path, entries[], truncated}); each entry is
 * {name, isDirectory, sizeBytes, modifiedUtc}. Mapping happens here so views never touch
 * raw Record<string, Object>.
 */

export class FileEntryModel {
  name: string = ''
  isDirectory: boolean = false
  sizeBytes: number = 0
  modifiedMs: number = 0

  static fromRecord(record: Record<string, Object>): FileEntryModel {
    const model = new FileEntryModel()
    model.name = (record['name'] as string) ?? ''
    model.isDirectory = (record['isDirectory'] as boolean) ?? false
    model.sizeBytes = (record['sizeBytes'] as number) ?? 0
    const modifiedUtc = record['modifiedUtc'] as string
    model.modifiedMs = modifiedUtc ? Date.parse(modifiedUtc) : 0
    return model
  }
}

export class FileListingModel {
  path: string = ''
  entries: FileEntryModel[] = []
  truncated: boolean = false

  static fromRecord(record: Record<string, Object>): FileListingModel {
    const model = new FileListingModel()
    model.path = (record['path'] as string) ?? ''
    model.truncated = (record['truncated'] as boolean) ?? false
    const rawEntries = record['entries'] as Record<string, Object>[]
    if (rawEntries) {
      for (let i = 0; i < rawEntries.length; i++) {
        model.entries.push(FileEntryModel.fromRecord(rawEntries[i]))
      }
    }
    return model
  }
}

export class DownloadPollState {
  status: string = 'pending'
  downloadUrl: string = ''
  errorMessage: string = ''

  static fromRecord(record: Record<string, Object>): DownloadPollState {
    const state = new DownloadPollState()
    state.status = (record['status'] as string) ?? 'pending'
    state.downloadUrl = (record['downloadUrl'] as string) ?? ''
    const error = record['error'] as Record<string, Object>
    if (error) {
      state.errorMessage = (error['message'] as string) ?? ''
    }
    return state
  }
}

export class UploadInitModel {
  requestId: string = ''
  uploadUrl: string = ''
}
