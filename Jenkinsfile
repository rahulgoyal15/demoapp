pipeline {
  agent any
  stages {
    stage('checkout-git') {
      steps {
        git(url: 'https://github.com/rahulgoyal15/demoapp.git', branch: 'master')
      }
    }
    stage('build_war') {
      steps {
        bat 'mvn clean install'
      }
    }
    stage('job completed') {
      steps {
        echo 'working fine'
      }
    }
  }
}