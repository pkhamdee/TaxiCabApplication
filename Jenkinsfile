#!/usr/bin/env groovy
properties([
    parameters([
        string(defaultValue: "master", description: 'Which Git Branch to clone?', name: 'GIT_BRANCH'),
        string(defaultValue: "1234567", description: 'AWS Account Number?', name: 'ACCOUNT'),
        string(defaultValue: "java-app", description: 'AWS ECR Repository where built docker images will be pushed.', name: 'ECR_REPO_NAME')
])
])
try
{
  stage('Clone Repo'){
    node('master'){
      cleanWs()
      checkout([$class: 'GitSCM', branches: [[name: '*/$GIT_BRANCH']], doGenerateSubmoduleConfigurations: false, extensions: [], submoduleCfg: [], userRemoteConfigs: [[url: 'git@github.com:powerupcloud/TaxiCabApplication.git']]])
    }
  }

  stage('Build Maven'){
    node('master'){
      withMaven(maven: 'apache-maven3.6'){
       sh "mvn clean package"
      } 
    }
  }

  stage('Build Docker Image') {
    node('master'){
      sh "\$(aws ecr get-login --no-include-email --region us-east-1)"
      GIT_COMMIT_ID = sh (
        script: 'git log -1 --pretty=%H',
        returnStdout: true
      ).trim()
      TIMESTAMP = sh (
        script: 'date +%Y%m%d%H%M%S',
        returnStdout: true
      ).trim()
      echo "Git commit id: ${GIT_COMMIT_ID}"
      IMAGETAG="${GIT_COMMIT_ID}-${TIMESTAMP}"
        sh "docker build -t ${ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/${ECR_REPO_NAME}:${IMAGETAG} ."
      sh "docker push ${ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/${ECR_REPO_NAME}:${IMAGETAG}"
    }
  }

  stage('Deploy on Dev') {
    node('master'){
        withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/dev-config","IMAGE=${ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/${ECR_REPO_NAME}:${IMAGETAG}"]){
        sh "sed -i 's|IMAGE|${IMAGE}|g' k8s/deployment.yaml"
        sh "sed -i 's|ACCOUNT|${ACCOUNT}|g' k8s/service.yaml"
        sh "sed -i 's|ENVIRONMENT|dev|g' k8s/*.yaml"
        sh "sed -i 's|BUILD_NUMBER|${BUILD_NUMBER}|g' k8s/*.yaml"
        sh "kubectl apply -f k8s"
        DEPLOYMENT = sh (
          script: 'cat k8s/deployment.yaml | yq -r .metadata.name',
          returnStdout: true
        ).trim()
        echo "Creating k8s resources..."
        sleep 180
        DESIRED= sh (
          script: "kubectl get deployment/$DEPLOYMENT | awk '{print \$2}' | grep -v DESIRED",
          returnStdout: true
         ).trim()
        CURRENT= sh (
          script: "kubectl get deployment/$DEPLOYMENT | awk '{print \$3}' | grep -v CURRENT",
          returnStdout: true
         ).trim()
        if (DESIRED.equals(CURRENT)) {
          currentBuild.result = "SUCCESS"
          return
        } else {
          error("Deployment Unsuccessful.")
        }
      }
    }
  }
  stage('Validate Dev Green Env') {
    node('master'){
      withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/dev-config"]){
        GREEN_SVC_NAME = sh (
          script: "yq .metadata.name k8s/service.yaml | tr -d '\"'",
          returnStdout: true
        ).trim()
        GREEN_LB = sh (
          script: "kubectl get svc ${GREEN_SVC_NAME} -o jsonpath=\"{.status.loadBalancer.ingress[*].hostname}\"",
          returnStdout: true
        ).trim()
        echo "Green ENV LB: ${GREEN_LB}"
        RESPONSE = sh (
          script: "curl -s -o /dev/null -w \"%{http_code}\" http://admin:password@${GREEN_LB}/swagger-ui.html -I",
          returnStdout: true
        ).trim()
          echo "${RESPONSE}"
        if (RESPONSE == "200") {
          echo "Application is working fine"
          sh "kubectl patch svc $GREEN_SVC_NAME -p \\\"{\\\"spec\\\":{\\\"selector\\\": {\\\"app\\\": \\\"taxicab\\\", \\\"version\\\": \\\"${BUILD_NUMBER}\\\"}}}\\\""
          sh "kubectl delete svc ${GREEN_SVC_NAME}"
        }
        else {
          echo "Application didnot pass the test case. Not Working"
          currentBuild.result = "FAILURE"
        }
      }
    }
  }
}
catch (err){
  currentBuild.result = "FAILURE"
  throw err
}
def userInput
try {
timeout(time: 60, unit: 'SECONDS') {
userInput = input message: 'Proceed to Production?', parameters: [booleanParam(defaultValue: false, description: 'Ticking this box will do a deployment on Prod', name: 'Deploy')]
}
}catch (err) {
    def user = err.getCauses()[0].getUser()
    echo "Aborted by:\n ${user}"
}

stage('Deploy on Prod') {
    node('master'){
      if (userInput == true) {
          echo "Deploying to Production..."       
       withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/prod-config","IMAGE=${ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/${ECR_REPO_NAME}:${IMAGETAG}"]){
        sh "sed -i 's|IMAGE|${IMAGE}|g' k8s/deployment.yaml"
        sh "sed -i 's|ACCOUNT|${ACCOUNT}|g' k8s/service.yaml"
        sh "sed -i 's|dev|prod|g' k8s/*.yaml"
        sh "kubectl apply -f k8s"
        DEPLOYMENT = sh (
          script: 'cat k8s/deployment.yaml | yq -r .metadata.name',
          returnStdout: true
        ).trim()
        echo "Creating k8s resources..."
        sleep 60
        DESIRED= sh (
          script: "kubectl get deployment/$DEPLOYMENT | awk '{print \$2}' | grep -v DESIRED",
          returnStdout: true
         ).trim()
        CURRENT= sh (
          script: "kubectl get deployment/$DEPLOYMENT | awk '{print \$3}' | grep -v CURRENT",
          returnStdout: true
         ).trim()
        if (DESIRED.equals(CURRENT)) {
          currentBuild.result = "SUCCESS"
          return
        } else {
          error("Deployment Unsuccessful.")
          currentBuild.result = "FAILURE"
        }
      }
    }
else {
        echo "Aborted Production Deployment..!!"
    } 
}
}
  stage('Validate Prod Green Env') {
    node('master'){
      withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/prod-config"]){
        GREEN_SVC_NAME = sh (
          script: "yq .metadata.name k8s/service.yaml | tr -d '\"'",
          returnStdout: true
        ).trim()
        GREEN_LB = sh (
          script: "kubectl get svc ${GREEN_SVC_NAME} -o jsonpath=\"{.status.loadBalancer.ingress[*].hostname}\"",
          returnStdout: true
        ).trim()
        echo "Green ENV LB: ${GREEN_LB}"
        RESPONSE = sh (
          script: "curl -s -o /dev/null -w \"%{http_code}\" http://admin:password@${GREEN_LB}/swagger-ui.html -I",
          returnStdout: true
        ).trim()
        if (RESPONSE == 200) {
          echo "Application is working fine. Patching Service."
          sh "kubectl patch svc taxicab-dev-svc -p '{\"spec\":{\"selector\": {\"app\": \"taxicab\", \"version\": \"${BUILD_NUMBER}\"}}}'"
          sh "kubectl delete svc ${GREEN_SVC_NAME}"
        }
        else {
          echo "Application didnot pass the test case. Not Working"
          currentBuild.result = "FAILURE"
        }
      }
    }
  }
