import { describe, expect, it } from '@ohos/hypium'
import { isAppVersionNewer, normalizeAppVersion } from '../main/ets/utils/AppVersionUtils'

export default function appVersionUtilsTest() {
  describe('appVersionUtilsTest', () => {
    it('normalizes_github_release_tags', 0, () => {
      expect(normalizeAppVersion('v1.2.2')).assertEqual('1.2.2')
      expect(normalizeAppVersion(' V1.3.0 ')).assertEqual('1.3.0')
    })

    it('compares_numeric_version_segments', 0, () => {
      expect(isAppVersionNewer('v1.2.3', '1.2.2')).assertTrue()
      expect(isAppVersionNewer('v1.10.0', '1.2.2')).assertTrue()
      expect(isAppVersionNewer('1.2.2', '1.2.2')).assertFalse()
      expect(isAppVersionNewer('1.2.1', '1.2.2')).assertFalse()
    })

    it('rejects_invalid_versions', 0, () => {
      expect(isAppVersionNewer('latest', '1.2.2')).assertFalse()
      expect(isAppVersionNewer('1.2.3', 'unknown')).assertFalse()
    })
  })
}
