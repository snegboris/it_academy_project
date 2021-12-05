def stagestatus = [:]

pipeline {
  triggers { pollSCM 'H * * * 1-5' }
  environment {
    imagename = "snegboris/project"
    registry = "registry.hub.docker.com"
  }
  agent any

  stages {

    stage('Checkout Source') {
      steps {
        git url:'https://github.com/snegboris/it_academy_project.git', branch:'master'
      }
    }

    stage("Build image") {
      steps {
        script {
          try {
            myapp = docker.build("$imagename:${env.BUILD_ID}")
            stagestatus.Docker_BUILD = "Success"
          } catch (Exception err) {
            stagestatus.Docker_BUILD = "Failure"
            error "Something wrong with Dockerfile"
          }
        }
      }
    }

    stage('Tests') {
      parallel {
        stage('Test image') {
          when { expression { stagestatus.find{ it.key == "Docker_BUILD" }?.value == "Success" } }
          steps {
            script {
              myapp.inside("--entrypoint=''") { sh './test/test.sh Image > image.log' }
              archiveArtifacts artifacts: 'image.log'
              catchError (buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                try {
                  sh 'grep SUCCESSFUL image.log'
                  stagestatus.Docker_TEST = "Success"
                } catch (Exception err) {
                  stagestatus.Docker_TEST = "Failure"
                  error "Image test failed"
                }
              }
            }
          }
        }
        stage('Kubeval') {
          agent { label 'slave' }
          steps {
            script {
              catchError (buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                try {
                  sh 'kubeval --strict --schema-location https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/ deployment/wordpress.yaml > kubeval.log'
                  archiveArtifacts artifacts: 'kubeval.log'
                  stagestatus.Kubeval = "Success"
                } catch (Exception err) {
                  stagestatus.Kubeval = "Failure"
                  error "Kubeval failed"
                }
              }
            }
          }
        }
      }
    }

    stage("Push image") {
      when { expression { stagestatus.find{ it.key == "Docker_TEST" }?.value == "Success" } }
      steps {
        script {
          catchError (buildResult: 'SUCCESS', stageResult: 'FAILURE') {
            try {
              docker.withRegistry('https://$registry', 'dockerhub') {
              myapp.push("${env.BUILD_ID}")
              }
              stagestatus.Docker_PUSH = "Success"
            } catch (Exception err) {
              stagestatus.Docker_PUSH = "Failure"
              error "Image pushing error"
              }
          }
        }
      }
    }

    stage("Clear images") {
      when { expression { stagestatus.find{ it.key == "Docker_BUILD" }?.value == "Success" } }
      steps {
        script {
          if ( stagestatus.find{ it.key == "Docker_PUSH" }?.value == "Success" ) {
            sh "docker rmi $registry/$imagename:${env.BUILD_ID}"
            sh "docker rmi $imagename:${env.BUILD_ID}"
          }
          else {
            sh "docker rmi $imagename:${env.BUILD_ID}"
          }
        }
      }
    }

    stage("Deploy/Upgrade") {
      when { 
        allOf {
          expression { stagestatus.find{ it.key == "Docker_PUSH" }?.value == "Success" }
          expression { stagestatus.find{ it.key == "Kubeval" }?.value == "Success" }
        }
      }
      steps {
        script {
          catchError (buildResult: 'SUCCESS', stageResult: 'FAILURE') {
            try {
              if (sh(returnStdout: true, script: 'kubectl get deployment wordpress --ignore-not-found --namespace default') == '') {
                sh """
                    sed -i "s|image_variable|$imagename:${env.BUILD_ID}|g" deployment/wordpress.yaml
                    kubectl apply -f deployment/wordpress.yaml --namespace=default
                  """
              }
              else {
                sh "kubectl scale --replicas=0 deployment/wordpress --namespace default"
                sh "kubectl delete -l name=wp-pv-claim -f deployment/wordpress.yaml --namespace default"
                sh "kubectl apply -l name=wp-pv-claim -f deployment/wordpress.yaml --namespace default"
                sh "kubectl set image deployment/wordpress wordpress=$imagename:${env.BUILD_ID} --namespace default"
                sh "kubectl scale --replicas=1 deployment/wordpress --namespace default"
                stagestatus.Upgrade = "Success"
              }
              sleep 5
              timeout(3) {
                waitUntil {
                  script {
                    def status = sh(returnStdout: true, script: "kubectl get pods --namespace default --selector=tier=frontend --no-headers -o custom-columns=':status.phase'")
                    if ( status =~ "Running") { return true }
                    else { return false }
                  }
                }
              }
              stagestatus.Deploy = "Success"
            } catch (Exception err) {
                stagestatus.Deploy = "Failure"
                stagestatus.Upgrade = "Failure"
                error "Deployment/Upgrade failed"
              }
          }
        }
      }
    }

    stage("Test Deployment") {
      agent { label 'slave' }
      when { expression { stagestatus.find{ it.key == "Deploy" }?.value == "Success" } }
      steps {
        script {
          sleep 60
          catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') { 
              if (stagestatus.find{ it.key == "Upgrade" }?.value == "Success") {
                sh './test/test.sh Upgrade > upgrade.log' 
                archiveArtifacts artifacts: 'upgrade.log'                
              }
              else {
                sh './test/test.sh Deploy > deploy.log' 
                archiveArtifacts artifacts: 'deploy.log'
              }
              try {
                if (stagestatus.find{ it.key == "Upgrade" }?.value == "Success") {
                  sh 'grep SUCCESSFUL upgrade.log'
                  stagestatus.Deploy_TEST = "Success"
                }
                else {
                  sh 'grep SUCCESSFUL deploy.log'
                  stagestatus.Deploy_TEST = "Success"
                }
              } catch (Exception err) {
              stagestatus.Deploy_TEST = "Failure"
              error "Test deploy/upgrade failed"
            }
          }
        }
      }
    }
   
    stage("Rollback") {
      when { 
        anyOf {
          expression { stagestatus.find{ it.key == "Upgrade" }?.value == "Failure" }
          expression { stagestatus.find{ it.key == "Deploy_TEST" }?.value == "Failure" }
        }
      }
      steps {
        script {
          sh "kubectl scale --replicas=0 deployment/wordpress --namespace default"
          sh "kubectl delete -l name=wp-pv-claim -f deployment/wordpress.yaml --namespace default"
          sh "kubectl apply -l name=wp-pv-claim -f deployment/wordpress.yaml --namespace default"
          sh "kubectl rollout undo deployment/wordpress --namespace default"
          sh "kubectl scale --replicas=1 deployment/wordpress --namespace default"
          sleep 5
          timeout(3) {
            waitUntil {
              script {
                def status = sh(returnStdout: true, script: "kubectl get pods --namespace default --selector=tier=frontend --no-headers -o custom-columns=':status.phase'")
                if ( status =~ "Running") { return true }
                else { return false }
              }
            }
          }
          currentBuild.result = 'FAILURE'
        }
      }
    }
  }

  post {
    always {
      script {
        results = ""
        stagestatus.each{entry -> results += "\n$entry.key: $entry.value"}  
        buildSummary = "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL}) ${results}" 
      }
    }
    success {
      slackSend (color: '#00FF00', message: "SUCCESSFUL: ${buildSummary}")
    }
    failure {
      slackSend (color: '#FF0000', message: "FAILED: ${buildSummary}")
    }
  }

}
