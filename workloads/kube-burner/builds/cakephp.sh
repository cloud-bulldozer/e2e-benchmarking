export APP=cakephp
# Concurrent Build Specific
export BUILD_IMAGE_STREAM=cakephp-mysql-example

export SOURCE_STRAT_ENV=COMPOSER_MIRROR
export SOURCE_STRAT_FROM_VERSION=7.4-ubi8

export SOURCE_STRAT_FROM=php
export POST_COMMIT_SCRIPT=./vendor/bin/phpunit


export BUILD_IMAGE=image-registry.openshift-image-registry.svc:5000/svt-${app}/${BUILD_IMAGE_STREAM}
export GIT_URL=https://github.com/sclorg/cakephp-ex.git
