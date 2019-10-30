#!/usr/bin/env groovy


pipeline {

  options {
    // Build auto timeout
    timeout(time: 60, unit: 'MINUTES')
  }

  // Some global default variables
  environment {
    DOCKER_REG = 'harbor.pcfgcp.pkhamdee.com'
    DOCKER_PROJ = 'library'
    IMAGE_NAME = 'java-app'
    GIT_BRANCH = 'master'
    KUBECONFIG = "$WORKSPACE/.kubeconfig"
    PROD_BLUE_SERVICE = 'taxicab-prod-svc'
  }

  // In this example, all is built and run from the master
  agent { node { label 'master' } }

  /*
  properties([
	  parameters([
      string (name: 'DOCKER_REG', defaultValue: 'harbor.pcfgcp.pkhamdee.com', description: 'Docker registry'),
      string (name: 'IMAGE_NAME', defaultValue: 'java-app', description: 'image name'),
      string (name: 'GIT_BRANCH', defaultValue: 'master', description: 'Which Git Branch to clone'),
      string (name: 'KUBECONFIG', defaultValue: "$WORKSPACE/.kubeconfig", description: 'kubeconfig'),
      string (name: 'PROD_BLUE_SERVICE', defaultValue: 'taxicab-prod-svc', description: 'Blue Service Name to patch in Prod Environment')
	  ])
  ])
  */
  
  //Pipelie stages
  stages {

    stage('Git clone and setup'){
      steps{
        echo "Check out code"

        cleanWs()

        echo "Check out TaxiCabApplication code"
                git branch: "master",                        
                        url: 'https://github.com/pkhamdee/TaxiCabApplication.git'

        withCredentials([file(credentialsId: 'letencrypt-ca-cert', variable: 'CA_CERT')]) {
          sh "cp ${CA_CERT} ${WORKSPACE}/ca.crt"
        }  

        //Check docker process
        sh "docker ps"

        // Validate kubectl
        withCredentials([file(credentialsId: 'kubernetes-config', variable: 'KUBECONFIG_SRC')]) {
          sh "cp ${KUBECONFIG_SRC} ${KUBECONFIG}"                    
          sh "kubectl config use-context dev1"
          sh "kubectl cluster-info"
        }  

        echo "DOCKER_REG is ${DOCKER_REG}"
      }
    }

    stage('Build Maven'){
      steps {
        //withMaven(maven: 'apache-maven3.6'){
          sh "mvn clean package"
        //} 
      }
    }

    stage('Build Docker Image') {
      steps {

        script {
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
        } 

        //build image
        sh "docker build -t ${DOCKER_REG}/${DOCKER_PROJ}/${IMAGE_NAME}:${IMAGETAG} ."

        //push image to registry
        echo "Pushing ${DOCKER_REG}/${DOCKER_PROJ}/${IMAGE_NAME}:${IMAGETAG} image to registry"

        withCredentials([usernamePassword(credentialsId: 'harbor-admin', passwordVariable: 'DOCKER_PSW', usernameVariable: 'DOCKER_USR')]) {                
          sh "docker login ${DOCKER_REG} -u ${DOCKER_USR} -p ${DOCKER_PSW}"
          sh "docker push ${DOCKER_REG}/${DOCKER_PROJ}/${IMAGE_NAME}:${IMAGETAG}"
        }  
      }
    }

    stage('Deploy on Dev') {
      steps {
        //withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/dev-config","IMAGE=${ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/${ECR_REPO_NAME}:${IMAGETAG}"]){
        sh "sed -i 's|IMAGE|${DOCKER_REG}/${DOCKER_PROJ}/${IMAGE_NAME}:${IMAGETAG}|g' k8s/deployment.yaml"
        sh "sed -i 's|ENVIRONMENT|dev|g' k8s/*.yaml"
        sh "sed -i 's|BUILD_NUMBER|01|g' k8s/*.yaml"

        sh "kubectl apply -f k8s -n taxicab"

        script {
          /*
          DEPLOYMENT = sh (
            script: 'cat k8s/deployment.yaml | yq -r .metadata.name',
            returnStdout: true
            ).trim()
          */

          DEPLOYMENT = "taxicap-dev-01"  

          echo "Creating k8s resources..."

          sleep 180

          DESIRED= sh (
            script: "kubectl get deployment/$DEPLOYMENT -n taxicab | awk '{print \$2}' | grep -v DESIRED",
            returnStdout: true
            ).trim()

          CURRENT= sh (
            script: "kubectl get deployment/$DEPLOYMENT -n taxicab | awk '{print \$3}' | grep -v CURRENT",
            returnStdout: true
            ).trim()

          if (DESIRED.equals(CURRENT)) {
            currentBuild.result = "SUCCESS"
            return
          } else {
            error("Deployment Unsuccessful.")
            currentBuild.result = "FAILURE"
            return
          }
        }
      }    
    }

    stage('Go for Production?') {
      steps {
        script {
          def userInput
          try {
            timeout(time: 60, unit: 'SECONDS') {
            userInput = input message: 'Proceed to Production?', parameters: [booleanParam(defaultValue: false, description: 'Ticking this box will do a deployment on Prod', name: 'DEPLOY_TO_PROD'),
                                                                 booleanParam(defaultValue: false, description: 'First Deployment on Prod?', name: 'PROD_BLUE_DEPLOYMENT')]}
          } catch (err) {
            def user = err.getCauses()[0].getUser()
            echo "Aborted by:\n ${user}"
            currentBuild.result = "SUCCESS"
            return
          }
        }
        
      }
    }

    stage('Deploy on Prod') {
      steps {
        script {
          if (userInput['DEPLOY_TO_PROD'] == true) {
            echo "Deploying to Production..."       
            //withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/prod-config","IMAGE=${ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/${ECR_REPO_NAME}:${IMAGETAG}"]){
            sh "sed -i 's|IMAGE|${DOCKER_REG}/${DOCKER_PROJ}/${IMAGE_NAME}:${IMAGETAG}|g' k8s/deployment.yaml"
            sh "sed -i 's|dev|prod|g' k8s/*.yaml"

            sh "kubectl apply -f k8s -n taxicab"

            /*
            DEPLOYMENT = sh (
              script: 'cat k8s/deployment.yaml | yq -r .metadata.name',
              returnStdout: true
              ).trim()
            */

            DEPLOYMENT = "taxicap-prod-01"

            echo "Creating k8s resources..."

            sleep 180

            DESIRED= sh (
              script: "kubectl get deployment/$DEPLOYMENT -n taxicab | awk '{print \$2}' | grep -v DESIRED",
              returnStdout: true
              ).trim()

            CURRENT= sh (
              script: "kubectl get deployment/$DEPLOYMENT -n taxicab | awk '{print \$3}' | grep -v CURRENT",
              returnStdout: true
              ).trim()

            if (DESIRED.equals(CURRENT)) {
              currentBuild.result = "SUCCESS"
            } else {
              error("Deployment Unsuccessful.")
              currentBuild.result = "FAILURE"
              return
            }
          
          } else {
            echo "Aborted Production Deployment..!!"
            currentBuild.result = "SUCCESS"
            return
          }
        }
      } 
    }

/*
    stage('Validate Prod Green Env') {
      steps {
        if (userInput['PROD_BLUE_DEPLOYMENT'] == false) {
          //withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/prod-config"]){
          GREEN_SVC_NAME = sh (
            script: "yq .metadata.name k8s/service.yaml | tr -d '\"'",
            returnStdout: true
            ).trim()

          GREEN_LB = sh (
            script: "kubectl get svc ${GREEN_SVC_NAME} -n taxicab -o jsonpath=\"{.status.loadBalancer.ingress[*].hostname}\"",
            returnStdout: true
            ).trim()

          echo "Green ENV LB: ${GREEN_LB}"
          RESPONSE = sh (
            script: "curl -s -o /dev/null -w \"%{http_code}\" http://admin:password@${GREEN_LB}/swagger-ui.html -I",
            returnStdout: true
          ).trim()

          if (RESPONSE == "200") {
            echo "Application is working fine. Proceeding to patch the service to point to the latest deployment..."
          } else {
            echo "Application didnot pass the test case. Not Working"
            currentBuild.result = "FAILURE"
          }
        }
      }
    }


    stage('Patch Prod Blue Service') {
      steps('master'){
        if (userInput['PROD_BLUE_DEPLOYMENT'] == false) {
        //withEnv(["KUBECONFIG=${JENKINS_HOME}/.kube/prod-config"]){
          BLUE_VERSION = sh (
            script: "kubectl get svc/${PROD_BLUE_SERVICE} -n taxicab -o yaml | yq .spec.selector.version",
            returnStdout: true
            ).trim()

          CMD = "kubectl get deployment -n taxicab -l version=${BLUE_VERSION} | awk '{if(NR>1)print \$1}'"
          
          BLUE_DEPLOYMENT_NAME = sh (
            script: "${CMD}",
            returnStdout: true
            ).trim()

          echo "${BLUE_DEPLOYMENT_NAME}"
          sh """kubectl patch svc  "${PROD_BLUE_SERVICE}" -n taxicab -p '{\"spec\":{\"selector\":{\"app\":\"taxicab\",\"version\":\"${BUILD_NUMBER}\"}}}'"""
          echo "Deleting Blue Environment..."
          sh "kubectl delete svc ${GREEN_SVC_NAME} -n taxicab"
          sh "kubectl delete deployment ${BLUE_DEPLOYMENT_NAME} -n taxicab"
        }
      }
    }

    */
  }
}