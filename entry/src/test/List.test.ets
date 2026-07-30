import localUnitTest from './LocalUnit.test';
import refactorGuardTest from './RefactorGuard.test';
import knowledgeSearchGuardTest from './KnowledgeSearchGuard.test';
import aiApiToolStreamStateTest from './AIApiToolStreamState.test';
import knowledgeEmbeddingBoundaryTest from './KnowledgeEmbeddingBoundary.test';
import knowledgeVectorProjectionTest from './KnowledgeVectorProjection.test';

export default function testsuite() {
  localUnitTest();
  refactorGuardTest();
  knowledgeSearchGuardTest();
  aiApiToolStreamStateTest();
  knowledgeEmbeddingBoundaryTest();
  knowledgeVectorProjectionTest();
}
