/**
 * @file Index.ets
 * @brief Artifacts feature HAR export barrel
 *
 * Exposes the WeChat-style artifact feed page used to exchange files between the
 * Console and the Worker over a session.
 */
export { ArtifactsPage } from './src/main/ets/view/ArtifactsPage'
export { ArtifactsPageRoute } from './src/main/ets/FeatureComponent'
export { ArtifactsService } from './src/main/ets/service/ArtifactsService'
export { FileCategory, ArtifactModel, mapArtifactModel } from './src/main/ets/model/ArtifactModels'
