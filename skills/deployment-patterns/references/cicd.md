# CI/CD Pipeline — Reference

> Read when: setting up CI/CD for Spring Boot projects (GitHub Actions, GitLab CI, or Jenkins).

## GitHub Actions — Full Pipeline

```yaml
name: CI/CD
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGISTRY: registry.example.com
  IMAGE_NAME: order-service

jobs:
  build-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U test"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
          cache: gradle

      - name: Build & Test
        run: ./gradlew build jacocoTestReport
        env:
          SPRING_R2DBC_URL: r2dbc:postgresql://localhost:5432/testdb
          SPRING_R2DBC_USERNAME: test
          SPRING_R2DBC_PASSWORD: test

      - name: Check Coverage
        run: ./gradlew jacocoTestCoverageVerification

      - name: Upload Coverage Report
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: build/reports/jacoco/

  security-scan:
    runs-on: ubuntu-latest
    needs: build-test
    steps:
      - uses: actions/checkout@v4
      - name: OWASP Dependency Check
        uses: dependency-check/Dependency-Check_Action@main
        with:
          project: ${{ env.IMAGE_NAME }}
          path: .
          format: HTML
      - name: Upload OWASP Report
        uses: actions/upload-artifact@v4
        with:
          name: owasp-report
          path: reports/

  docker-build:
    runs-on: ubuntu-latest
    needs: [build-test, security-scan]
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: Build & Push Docker Image
        run: |
          docker build -t $REGISTRY/$IMAGE_NAME:${{ github.sha }} .
          docker build -t $REGISTRY/$IMAGE_NAME:latest .
          docker push $REGISTRY/$IMAGE_NAME:${{ github.sha }}
          docker push $REGISTRY/$IMAGE_NAME:latest

      - name: Scan Image with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: table
          exit-code: 1
          severity: CRITICAL,HIGH

  deploy-staging:
    runs-on: ubuntu-latest
    needs: docker-build
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to Staging
        run: |
          kubectl set image deployment/$IMAGE_NAME \
            $IMAGE_NAME=$REGISTRY/$IMAGE_NAME:${{ github.sha }}
          kubectl rollout status deployment/$IMAGE_NAME --timeout=300s

  deploy-production:
    runs-on: ubuntu-latest
    needs: deploy-staging
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to Production (Canary)
        run: |
          kubectl set image deployment/$IMAGE_NAME \
            $IMAGE_NAME=$REGISTRY/$IMAGE_NAME:${{ github.sha }}
          kubectl rollout status deployment/$IMAGE_NAME --timeout=600s
```

## GitLab CI Variant

```yaml
stages: [build, test, security, docker, deploy]

variables:
  GRADLE_OPTS: "-Dorg.gradle.daemon=false"
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

build:
  stage: build
  image: eclipse-temurin:17-jdk
  script:
    - ./gradlew build -x test
  artifacts:
    paths: [build/libs/*.jar]

test:
  stage: test
  image: eclipse-temurin:17-jdk
  services:
    - postgres:15
  variables:
    POSTGRES_DB: testdb
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
  script:
    - ./gradlew test jacocoTestReport
  artifacts:
    reports:
      junit: build/test-results/test/*.xml

docker:
  stage: docker
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t $IMAGE .
    - docker push $IMAGE
  only: [main]

deploy:
  stage: deploy
  script:
    - kubectl set image deployment/order-service order-service=$IMAGE
    - kubectl rollout status deployment/order-service --timeout=300s
  only: [main]
  environment:
    name: production
```

## Deployment Strategies

| Strategy | Risk | Rollback Speed | Resource Cost |
|----------|------|----------------|---------------|
| Rolling Update | Low | Fast (K8s auto) | 1× + surge% |
| Blue/Green | Very Low | Instant (switch) | 2× |
| Canary | Very Low | Fast (scale down) | 1× + canary |
| Recreate | High | Slow (full restart) | 1× |

**Recommended:** Rolling Update for stateless services, Canary for critical services with traffic splitting (Istio/Linkerd).
