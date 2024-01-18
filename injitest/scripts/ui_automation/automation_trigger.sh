#!/bin/sh

#get from params
PLATFORM=$1
RUN_NAME=$2
TEST_TYPE=$3

echo "$PLATFORM"
echo "$RUN_NAME"
echo "$TEST_TYPE"

#can be here
PROJECT_ARN="arn:aws:devicefarm:us-west-2:931337674770:project:b356580b-c561-4fd2-bfdf-8993aebafc5a"
TEST_PACKAGE_FILE_TYPE="APPIUM_JAVA_TESTNG_TEST_PACKAGE"

#will be added later in script
APP_ARN=""
DEVICE_POOL_ARN=""
TEST_PACKAGE_ARN=""

#to get absolute path
PROJECT_PATH=$(pwd)

#configure based on platform
    if [ "$PLATFORM" == "Android" ]; then
        DEVICE_POOL_NAME="ANDROID DEVICE POOL"
        TEST_PACKAGE_PATH="../../target/zip-with-dependencies.zip"
        TEST_PACKAGE_NAME="Android-Test"
        TEST_SPEC_ARN="arn:aws:devicefarm:us-west-2::upload:100e31e8-12ac-11e9-ab14-d663b5a4a910"

        cd $PROJECT_PATH/../../../android/app/build/outputs/apk/inji/release/
        new_PATH=$(pwd)
        APP_PATH="$new_PATH/Inji_universal.apk"
        APP_NAME="Inji_universal.apk"
        APP_TYPE="ANDROID_APP"

    else
        DEVICE_POOL_NAME="IOS DEVICE POOL"
        TEST_PACKAGE_PATH="$PROJECT_PATH/../../target/zip-with-dependencies.zip"
        TEST_PACKAGE_NAME="IOS-Test"
        TEST_SPEC_ARN="arn:aws:devicefarm:us-west-2::upload:100e31e8-12ac-11e9-ab14-d663bd873c82"

        APP_PATH="$PROJECT_PATH/../../../ios/fastlane/Inji_artifacts/Inji.ipa"
        APP_NAME="Inji.ipa"
        APP_TYPE="IOS_APP"
    fi

#update xml based on platform
update_xml_configuration() {
    cd ../../src/main/resources
    
    if [ "$PLATFORM" == 'Android' ]; then
        if [ "$TEST_TYPE" == 'sanity' ]; then
            cat androidSanity.txt > testng.xml
        else
            cat androidRegression.txt > testng.xml
        fi
    elif [ "$PLATFORM" == 'IOS' ]; then
        if [ "$TEST_TYPE" == 'sanity' ]; then
            cat iosSanity.txt > testng.xml
        else
            cat iosRegression.txt > testng.xml
        fi
    fi

    cd ../../../
}

#upload artifacts to device farm
upload_to_device_farm() {
    local project_arn=$1
    local file_path=$2
    local file_name=$3
    local file_type=$4

    response=$(aws devicefarm create-upload --project-arn "$project_arn" --name "$file_name" --type "$file_type" --query 'upload.{url: url, arn: arn}' --output json)
    upload_url=$(echo "$response" | jq -r '.url')

    curl -T $file_path "$upload_url"
    echo "$response" | jq -r '.arn'
}

#trigger the run
start_run_on_device_farm() {
    local project_arn=$1
    local app_arn=$2
    local device_pool_arn=$3
    local test_package_arn=$4
    local test_spec_arn=$5
    local run_name=$6

    run_arn=$(aws devicefarm schedule-run --project-arn "$project_arn" --app-arn "$app_arn" --device-pool-arn "$device_pool_arn" --name "$run_name" --test testSpecArn=$test_spec_arn,type=APPIUM_JAVA_TESTNG,testPackageArn="$test_package_arn" --query run.arn --output text)

    echo "$run_arn"
}

#rewrite the xml file
update_xml_configuration

# #build the test jar
mvn clean package -DskipTests=true

#upload the jar and apk
TEST_PACKAGE_ARN=$(upload_to_device_farm $PROJECT_ARN $TEST_PACKAGE_PATH $TEST_PACKAGE_NAME $TEST_PACKAGE_FILE_TYPE)

#upload the app file
APP_ARN=$(upload_to_device_farm $PROJECT_ARN $APP_PATH $APP_NAME $APP_TYPE)

#list device pools and filter by name
DEVICE_POOL_ARN=$(aws devicefarm list-device-pools --arn $PROJECT_ARN --query "devicePools[?name=='$DEVICE_POOL_NAME'].arn" --output text)

# Start the run
run_arn=$(start_run_on_device_farm $PROJECT_ARN $APP_ARN $DEVICE_POOL_ARN $TEST_PACKAGE_ARN $TEST_SPEC_ARN $RUN_NAME)

echo "::set-output name=run_arn::$run_arn"