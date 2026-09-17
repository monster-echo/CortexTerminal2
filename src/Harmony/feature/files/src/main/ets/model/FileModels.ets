/**
 * @file FileModels.ets
 * @brief View models for the workspace-scoped remote file browser.
 *
 * The Gateway returns FileListing JSON ({path, entries[], truncated}); each entry is
 * {name, isDirectory, sizeBytes, modifiedUtc}. Transfer init responses carry a list of
 * candidate endpoints (端点协商：LAN 直连 → Relay 兜底)；Mapping happens here so views
 * never touch raw Record<string, Object>.
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

export class TransferEndpointModel {
  url: string = ''
  kind: string = ''

  static fromRecord(record: Record<string, Object>): TransferEndpointModel {
    const model = new TransferEndpointModel()
    model.url = (record['url'] as string) ?? ''
    model.kind = (record['kind'] as string) ?? ''
    return model
  }
}

export class WorkspaceModel {
  id: string = ''
  workerId: string = ''
  name: string = ''
  rootPath: string = ''
  isDefault: boolean = false

  static fromRecord(record: Record<string, Object>): WorkspaceModel {
    const model = new WorkspaceModel()
    model.id = (record['id'] as string) ?? ''
    model.workerId = (record['workerId'] as string) ?? ''
    model.name = (record['name'] as string) ?? ''
    model.rootPath = (record['rootPath'] as string) ?? ''
    model.isDefault = (record['isDefault'] as boolean) ?? false
    return model
  }
}

export class UploadInitModel {
  transferId: string = ''
  endpoints: TransferEndpointModel[] = []
}

export class DownloadInitModel {
  transferId: string = ''
  sizeBytes: number = 0
  filename: string = ''
  endpoints: TransferEndpointModel[] = []
}
