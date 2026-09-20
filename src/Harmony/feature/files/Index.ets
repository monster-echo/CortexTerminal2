/**
 * @file Index.ets
 * @brief Files feature HAR export barrel
 *
 * Exposes the remote folder manager used to browse the session root and move
 * files between the Console and the Worker on demand.
 */
export { FileBrowserPage } from './src/main/ets/view/FileBrowserPage'
export { FilePreviewPage } from './src/main/ets/view/FilePreviewPage'
export { FilesPageRoute } from './src/main/ets/FeatureComponent'
export { FilesService } from './src/main/ets/service/FilesService'
export { FileEntryModel, FileListingModel } from './src/main/ets/model/FileModels'
