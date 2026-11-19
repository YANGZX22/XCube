import { describe, it, expect } from '@ohos/hypium'
import { editSkillEntry, normalizeSkillBundle, packSkill, readPackedSkillFile, readSkillMetadata, readStoredSkillMetadata,
  SKILL_ENTRY, SkillFile, skillFileText, skillLinkTarget, skillTextFile, unpackSkill } from '../main/ets/utils/SkillPackage'

export default function skillPackageTest() {
  describe('SkillPackage', () => {
    it('reads_yaml_and_preserves_extra_fields_when_editing_the_entry', 0, () => {
      const input = '---\r\nname: "writing-kit"\r\ndescription: >-\r\n  Writes clear\r\n  reports.\r\n' +
        'metadata:\r\n  author: Cube\r\ndisable-model-invocation: true\r\n---\r\n# Main\r\n'
      const meta = readSkillMetadata(input, '')
      expect(meta.name).assertEqual('writing-kit')
      expect(meta.description).assertEqual('Writes clear reports.')
      expect(meta.manualOnly).assertTrue()
      expect(editSkillEntry(input, meta.name, meta.description, meta.body)).assertEqual(input)
      const changed = editSkillEntry(input, 'new-name', 'New description', '# New')
      expect(changed.includes('author: Cube')).assertTrue()
      expect(readSkillMetadata(changed, '').manualOnly).assertTrue()
      expect(readSkillMetadata(changed, '').name).assertEqual('new-name')
      expect(readSkillMetadata(changed, '').body).assertEqual('# New')
    })

    it('keeps_legacy_markdown_and_fills_an_omitted_name_when_renamed', 0, () => {
      const legacy = '---\nname: [unfinished\n---\n# Notes'
      expect(readStoredSkillMetadata(legacy, 'Legacy', '').body).assertEqual(legacy)
      const original = '\uFEFF---\ndescription: A guide\n---\nMain'
      expect(skillFileText(skillTextFile(SKILL_ENTRY, original))).assertEqual(original)
      const renamed = editSkillEntry(original, 'new-name', 'A guide', 'Main', 'folder-name', 'A guide')
      expect(readSkillMetadata(renamed, '').name).assertEqual('new-name')
    })

    it('keeps_nested_documents_and_binary_resources_through_a_package_round_trip', 0, () => {
      const files = [skillTextFile('demo/SKILL.md', '[Guide](references/guide.md)'),
        skillTextFile('demo/references/guide.md', '说明'), skillTextFile('demo/examples/guide.md', 'Example'),
        new SkillFile('demo/assets/template.bin', new Uint8Array([0, 255, 1]))]
      expect(normalizeSkillBundle(files).name).assertEqual('demo')
      const bytes = packSkill(files)
      const unpacked = unpackSkill(bytes).files
      expect(unpacked.length).assertEqual(4)
      expect(unpacked[0].path).assertEqual(SKILL_ENTRY)
      expect(skillFileText(readPackedSkillFile(bytes, 'references/guide.md'))).assertEqual('说明')
      expect(skillFileText(readPackedSkillFile(bytes, 'examples/guide.md'))).assertEqual('Example')
      expect(readPackedSkillFile(bytes, 'assets/template.bin').bytes[1]).assertEqual(255)
    })

    it('resolves_markdown_links_relative_to_the_open_document', 0, () => {
      expect(skillLinkTarget('references/guide.md', '../examples/%E7%A4%BA%E4%BE%8B.md#demo')).assertEqual('examples/示例.md')
      expect(skillLinkTarget(SKILL_ENTRY, './references/guide.md')).assertEqual('references/guide.md')
      expect(skillLinkTarget(SKILL_ENTRY, '../private.md')).assertEqual('')
      expect(skillLinkTarget(SKILL_ENTRY, 'https://example.com/guide.md')).assertEqual('')
    })

    it('requires_one_root_and_rejects_duplicate_or_escaping_paths', 0, () => {
      const cases: string[][] = [['a/SKILL.md', 'b/SKILL.md'], ['references/guide.md'],
        [SKILL_ENTRY, '../elsewhere.md'], [SKILL_ENTRY, 'refs/a.md', 'refs/a.md']]
      for (const paths of cases) {
        let failed = false
        try {
          normalizeSkillBundle(paths.map((path: string): SkillFile => skillTextFile(path, 'test')))
        } catch {
          failed = true
        }
        expect(failed).assertTrue()
      }
    })
  })
}
