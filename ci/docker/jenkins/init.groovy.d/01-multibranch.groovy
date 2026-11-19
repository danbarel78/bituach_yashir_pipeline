// Creates the Multibranch Pipeline job on first start.
//
// Why Groovy and not Jenkinsfile-only: the job object (branch source, script
// path, scan interval) is not described by the Jenkinsfile. Creating it here
// means a fresh JENKINS_HOME comes up with the job already present, instead of
// requiring manual clicks that nobody can reproduce.
//
// Idempotent: if the job already exists, nothing happens.

import hudson.triggers.TimerTrigger
import jenkins.branch.BranchSource
import jenkins.model.Jenkins
import jenkins.plugins.git.GitSCMSource
import jenkins.plugins.git.traits.BranchDiscoveryTrait
import jenkins.plugins.git.traits.LocalBranchTrait
import jenkins.scm.impl.trait.RegexSCMHeadFilterTrait
import org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory
import org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject

final String JOB_NAME = 'bituach-yashir'
final String REPO_URL = 'https://github.com/danbarel78/bituach_yashir_pipeline.git'
final String BRANCH_REGEX = '^(develop|main|release/.+|hotfix/.+|feature/.+|bugfix/.+|chore/.+|docs/.+|refactor/.+|test/.+|dependabot/.+)$'

def jenkins = Jenkins.get()

if (jenkins.getItem(JOB_NAME) != null) {
  println("init: job '${JOB_NAME}' already exists - leaving it alone")
  return
}

def source = new GitSCMSource(
  null,          // id
  REPO_URL,
  null,          // credentialsId: the repository is public
  '*',           // includes
  '',            // excludes
  false          // ignoreOnPushNotifications
)
source.setTraits([
  new BranchDiscoveryTrait(),
  new LocalBranchTrait(),
  new RegexSCMHeadFilterTrait(BRANCH_REGEX)
])

def factory = new WorkflowBranchProjectFactory()
factory.setScriptPath('ci/Jenkinsfile')

def project = jenkins.createProject(WorkflowMultiBranchProject, JOB_NAME)
project.setDescription('Bituach Yashir - build/test/scan/push and GitOps digest update. Branch-driven.')
project.getSourcesList().add(new BranchSource(source))
project.setProjectFactory(factory)

// Folder-level indexing every 5 minutes. Per-branch polling (1 minute) is
// declared inside the Jenkinsfile.
project.addTrigger(new TimerTrigger('H/5 * * * *'))
project.save()

println("init: created Multibranch Pipeline '${JOB_NAME}' for ${REPO_URL}")