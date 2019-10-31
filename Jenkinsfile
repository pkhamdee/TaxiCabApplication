#!/usr/bin/env groovy

def userInput

/* Create the kubernetes namespace */
def createNamespace (namespace) {
    echo "Creating namespace ${namespace} if needed"

    sh "[ ! -z \"\$(kubectl get ns ${namespace} -o name 2>/dev/null)\" ] || kubectl create ns ${namespace}"
}

/* Run a curl against a given url */
def curlRun (url, out) {
    echo "Running curl on ${url}"

    script {
        if (out.equals('')) {
            out = 'http_code'
        }
        echo "Getting ${out}"
                def result = sh (
                returnStdout: true,
                script: "curl --output /dev/null --silent --connect-timeout 5 --max-time 5 --retry 5 --retry-delay 5 --retry-max-time 30 --write-out \"%{${out}}\" ${url}"
        )
        echo "Result (${out}): ${result}"
    }
}


pipeline {

  // Build auto timeout
  options {
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
  
  //Pipelie stages
  stages {

    stage('Git clone and setup'){
      steps{
        echo "Check out code"

        cleanWs()

        //get checkout
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

        //create namespace taxicab
        script {
          namespace = 'taxicab-dev'
          createNamespace (namespace)   
        }

        script {
          namespace = 'taxicab-prod'
          createNamespace (namespace)   
        }

      }
    }

    stage('Build Maven'){
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {
        sh "mvn clean package"
      }
    }

    stage('Build Docker Image') {
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {

        script {
          GIT_COMMIT_ID = sh (
            script: 'git log -1 --pretty=%h',
            returnStdout: true
            ).trim()

          TIMESTAMP = sh (
            script: 'date +%Y%m%d%H%M%S',
            returnStdout: true
            ).trim()

          echo "Git commit id: ${GIT_COMMIT_ID}"

          //IMAGETAG="${GIT_COMMIT_ID}-${TIMESTAMP}"
          IMAGETAG="${GIT_COMMIT_ID}"

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
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {

        sh "sed -i 's|IMAGE|${DOCKER_REG}/${DOCKER_PROJ}/${IMAGE_NAME}:${IMAGETAG}|g' k8s/deployment.yaml"
        sh "sed -i 's|ENVIRONMENT|dev01|g' k8s/*.yaml"
        sh "sed -i 's|BUILD_NUMBER|${BUILD_NUMBER}|g' k8s/*.yaml"

        script {

          sh "kubectl apply -f k8s -n taxicab-dev" 

          DEPLOYMENT = "taxicab-dev01-${BUILD_NUMBER}"  

          echo "Creating k8s ${DEPLOYMENT} resources..."

          sleep 180

          DESIRED= sh (
            script: "kubectl get deployment/$DEPLOYMENT -n taxicab-dev | awk '{print \$2}' | grep -v READY | awk -F'/' '{print \$1}'",
            returnStdout: true
            ).trim()

          CURRENT= sh (
            script: "kubectl get deployment/$DEPLOYMENT -n taxicab-dev | awk '{print \$2}' | grep -v READY | awk -F'/' '{print \$2}'",
            returnStdout: true
            ).trim()

          if (DESIRED.equals(CURRENT)) {
            currentBuild.result = "SUCCESS"

          } else {
            error("Deployment Unsuccessful.")
            currentBuild.result = "FAILURE"
            return
          }
        }
      }    
    }

    stage('Dev tests') {
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {
        echo "Dev tests"

        script {
          DEV_ING_NAME = "taxicab-dev01-${BUILD_NUMBER}"

          DEV_LB = sh (
            script: "kubectl get ing ${DEV_ING_NAME} -n taxicab-dev | awk '{print \$2}' | grep -v HOSTS",
            returnStdout: true
            ).trim()

          echo "Dev ENV LB: ${DEV_LB}"
          
          RESPONSE = sh (
            returnStdout: true,
            script: "curl --output /dev/null --silent --connect-timeout 5 --max-time 5 --retry 5 --retry-delay 5 --retry-max-time 30 --write-out \"%{http_code}\" http://admin:password@${DEV_LB}/swagger-ui.html"
            )

          echo "RESPONSE : ${RESPONSE}"  

          if (RESPONSE == "200") {
            echo "Application is working fine. Proceeding to patch the service to point to the latest deployment..."

          } else {

            echo "Application didnot pass the test case. Not Working"
            currentBuild.result = "FAILURE"
            return
          }

        }

      }
    }

    stage('Cleanup on Dev') {
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {
        echo "Cleanup Dev"
        sh "kubectl delete -f k8s -n taxicab-dev"
      }
    }    

    stage('Go for Production?') {
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {
        script {
            userInput = input message: 'Proceed to Production?', 
                            parameters: [booleanParam(defaultValue: false, description: 'Ticking this box will do a deployment on Prod', name: 'DEPLOY_TO_PROD'),
                                         booleanParam(defaultValue: false, description: 'First Deployment on Prod?', name: 'PROD_BLUE_DEPLOYMENT')]
        }
      }
    }

    stage('Deploy on Prod') {
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {
        script {
          if (userInput['DEPLOY_TO_PROD'] == true) {
            echo "Deploying to Production..."       

            sh "sed -i 's|dev01|prod|g' k8s/*.yaml"

            sh "kubectl apply -f k8s -n taxicab-prod"

            DEPLOYMENT = "taxicab-prod-${BUILD_NUMBER}"

            echo "Creating k8s ${DEPLOYMENT} resources..."

            sleep 180

            DESIRED= sh (
              script: "kubectl get deployment/$DEPLOYMENT -n taxicab-prod | awk '{print \$2}' | grep -v READY | awk -F'/' '{print \$1}'",
              returnStdout: true
              ).trim()

            CURRENT= sh (
              script: "kubectl get deployment/$DEPLOYMENT -n taxicab-prod | awk '{print \$2}' | grep -v READY | awk -F'/' '{print \$2}'",
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


    stage('Validate Prod Green Env') {
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {

        script {
          if (userInput['PROD_BLUE_DEPLOYMENT'] == false) {

            GREEN_ING_NAME = "taxicab-prod-${BUILD_NUMBER}"

            GREEN_LB = sh (
              script: "kubectl get ing ${GREEN_ING_NAME} -n taxicab-prod | awk '{print \$2}' | grep -v HOSTS",
              returnStdout: true
              ).trim()

            echo "Green ENV LB: ${GREEN_LB}"

            RESPONSE = sh (
              script: "curl --output /dev/null --silent --connect-timeout 5 --max-time 5 --retry 5 --retry-delay 5 --retry-max-time 30 --write-out \"%{http_code}\" http://admin:password@${GREEN_LB}/swagger-ui.html",
              returnStdout: true
              )

            if (RESPONSE == "200") {
              echo "Application is working fine. Proceeding to patch the service to point to the latest deployment..."

            } else {
              
              //rollback
              sh "kubectl delete -f k8s -n taxicab-prod"   

              echo "Application didnot pass the test case. Not Working"
              currentBuild.result = "FAILURE"
              return
            }
 

          }  
        }
      }
    }


    stage('Patch Prod Blue Service') {
      when {
        allOf {
          expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
        }
      }
      steps {
        script {
          if (userInput['PROD_BLUE_DEPLOYMENT'] == false) {
          
            BLUE_VERSION = sh (
              script: "kubectl get svc/${PROD_BLUE_SERVICE} -n taxicab-prod -o jsonpath=\"{.spec.selector.version}\"",
              returnStdout: true
              ).trim()

            CMD = "kubectl get deployment -n taxicab-prod -l version=${BLUE_VERSION} | awk '{if(NR>1)print \$1}'"
          
            BLUE_DEPLOYMENT_NAME = sh (
              script: "${CMD}",
              returnStdout: true
              ).trim()

            BLUE_SVC_NAME = "taxicab-prod-svc-${BLUE_VERSION}"  

            BLUE_ING_NAME = "taxicab-prod-${BLUE_VERSION}"

            sh """kubectl patch svc "${PROD_BLUE_SERVICE}" -n taxicab-prod -p '{\"spec\":{\"selector\":{\"app\":\"taxicab\",\"version\":\"${BUILD_NUMBER}\"}}}'"""

            echo "Deleting Blue Environment... service = ${BLUE_SVC_NAME}, deployment = ${BLUE_DEPLOYMENT_NAME}"
            sh "kubectl delete svc ${BLUE_SVC_NAME} -n taxicab-prod"
            sh "kubectl delete deployment ${BLUE_DEPLOYMENT_NAME} -n taxicab-prod"
            sh "kubectl delete ingress ${BLUE_ING_NAME} -n taxicab-prod"

          } else {
            echo "Create new ${PROD_BLUE_SERVICE}"
            sh "sed -i 's|taxicab-prod-svc-${BUILD_NUMBER}|${PROD_BLUE_SERVICE}|g' k8s/service.yaml"
            sh "sed -i 's|taxicab-prod-${BUILD_NUMBER}|taxicab-prod|g' k8s/ingress.yaml"
            sh "kubectl apply -f k8s/service.yaml -n taxicab-prod"
            sh "kubectl apply -f k8s/ingress.yaml -n taxicab-prod"
          }
        }  
      }
    }
  }
}