import localUnitTest from './LocalUnit.test';
import refactorGuardTest from './RefactorGuard.test';
import knowledgeSearchGuardTest from './KnowledgeSearchGuard.test';
import aiApiToolStreamStateTest from './AIApiToolStreamState.test';
import knowledgeEmbeddingBoundaryTest from './KnowledgeEmbeddingBoundary.test';
import knowledgeVectorProjectionTest from './KnowledgeVectorProjection.test';
import knowledgeVectorBootstrapGateTest from './KnowledgeVectorBootstrapGate.test';
import knowledgeSemanticChunkerTest from './KnowledgeSemanticChunker.test';
import chatMessageTreeHelperTest from './ChatMessageTreeHelper.test';
import knowledgeVectorStartupCoordinatorTest from './KnowledgeVectorStartupCoordinator.test';
import knowledgeVectorRecoveryPolicyTest from './KnowledgeVectorRecoveryPolicy.test';

export default function testsuite() {
  localUnitTest();
  refactorGuardTest();
  knowledgeSearchGuardTest();
  aiApiToolStreamStateTest();
  knowledgeEmbeddingBoundaryTest();
  knowledgeVectorProjectionTest();
  knowledgeVectorBootstrapGateTest();
  knowledgeSemanticChunkerTest();
  chatMessageTreeHelperTest();
  knowledgeVectorStartupCoordinatorTest();
  knowledgeVectorRecoveryPolicyTest();
}
