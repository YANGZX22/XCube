import { describe, expect, it } from '@ohos/hypium'
import { parsePdfPageSelection } from '../main/ets/services/PdfTextExtractionService'

function joinPages(pages: number[]): string {
  return pages.join(',')
}

export default function pdfPageSelectionTest() {
  describe('pdfPageSelectionTest', () => {
    it('takes_the_first_pages_when_no_range_is_given', 0, () => {
      expect(joinPages(parsePdfPageSelection('', 10, 4))).assertEqual('1,2,3,4')
      expect(joinPages(parsePdfPageSelection('   ', 2, 4))).assertEqual('1,2')
    })

    it('reads_single_pages_ranges_and_mixed_lists', 0, () => {
      expect(joinPages(parsePdfPageSelection('3', 10, 4))).assertEqual('3')
      expect(joinPages(parsePdfPageSelection('2-5', 10, 8))).assertEqual('2,3,4,5')
      expect(joinPages(parsePdfPageSelection('2,4,7-9', 10, 8))).assertEqual('2,4,7,8,9')
      expect(joinPages(parsePdfPageSelection(' 1 , 3 ', 10, 8))).assertEqual('1,3')
    })

    it('accepts_a_reversed_range', 0, () => {
      expect(joinPages(parsePdfPageSelection('5-2', 10, 8))).assertEqual('2,3,4,5')
    })

    it('drops_out_of_range_and_duplicate_pages', 0, () => {
      expect(joinPages(parsePdfPageSelection('0,1,1,4', 3, 8))).assertEqual('1')
      expect(joinPages(parsePdfPageSelection('2-99', 4, 8))).assertEqual('2,3,4')
      expect(joinPages(parsePdfPageSelection('11-20', 5, 8))).assertEqual('')
    })

    it('never_returns_more_than_max_pages', 0, () => {
      expect(joinPages(parsePdfPageSelection('1-50', 50, 3))).assertEqual('1,2,3')
      expect(joinPages(parsePdfPageSelection('', 50, 1))).assertEqual('1')
      // A zero or negative cap still yields one page rather than an empty read.
      expect(joinPages(parsePdfPageSelection('4-9', 20, 0))).assertEqual('4')
    })

    it('ignores_junk_segments_instead_of_failing', 0, () => {
      expect(joinPages(parsePdfPageSelection('abc,2,,-,3', 10, 8))).assertEqual('2,3')
      expect(joinPages(parsePdfPageSelection('abc', 10, 8))).assertEqual('')
    })
  })
}
