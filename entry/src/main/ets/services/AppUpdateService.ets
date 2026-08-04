import { getHttpService, HttpResponse, HttpService } from './HttpService'
import { isAppVersionNewer, normalizeAppVersion } from '../utils/AppVersionUtils'

export const XCUBE_RELEASES_URL = 'https://github.com/YANGZX22/XCube/releases'
const XCUBE_LATEST_RELEASE_API_URL = 'https://api.github.com/repos/YANGZX22/XCube/releases/latest'

interface GitHubLatestReleasePayload {
  tag_name?: string
  name?: string
  body?: string
}

export class AppUpdateInfo {
  hasUpdate: boolean = false
  latestVersion: string = ''
  releaseName: string = ''
  releaseNotes: string = ''
  releaseUrl: string = XCUBE_RELEASES_URL
}

export class AppUpdateService {
  private static instance: AppUpdateService | null = null
  private httpService: HttpService = getHttpService()

  private constructor() {}

  static getInstance(): AppUpdateService {
    if (AppUpdateService.instance === null) {
      AppUpdateService.instance = new AppUpdateService()
    }
    return AppUpdateService.instance
  }

  async checkForUpdate(currentVersion: string): Promise<AppUpdateInfo> {
    const headers: Record<string, string> = {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': `XCube/${currentVersion}`
    }
    const response: HttpResponse = await this.httpService.get(XCUBE_LATEST_RELEASE_API_URL, headers,
      { timeout: 15000 })
    if (!response.success) {
      const detail = response.errorMessage !== '' ? response.errorMessage : `HTTP ${response.statusCode}`
      throw new Error(`GitHub release request failed: ${detail}`)
    }

    let payload: GitHubLatestReleasePayload
    try {
      payload = JSON.parse(response.data) as GitHubLatestReleasePayload
    } catch (error) {
      throw new Error(`Invalid GitHub release response: ${JSON.stringify(error)}`)
    }

    const tagName = payload.tag_name ?? ''
    const latestVersion = normalizeAppVersion(tagName)
    if (latestVersion === '') {
      throw new Error('GitHub release response does not contain a version tag')
    }

    const result = new AppUpdateInfo()
    result.latestVersion = latestVersion
    result.releaseName = (payload.name ?? '').trim()
    result.releaseNotes = (payload.body ?? '').trim()
    result.hasUpdate = isAppVersionNewer(latestVersion, currentVersion)
    return result
  }
}

export function getAppUpdateService(): AppUpdateService {
  return AppUpdateService.getInstance()
}
