#!/bin/bash

#
# Utility function to check return values on commands
#
function checkrv {
  if [ $1 -gt 0 ]; then
    echo "$2 failed with return value $1"
    exit 1
  else
    echo "$2 succeeded return value $1"
  fi
}

#
# function to rebuild with a specific profile
# profile_rebuild <profile>
#
function profile_rebuild {
  local profile=$1

  pushd geoserver/web/app
  $MVN -s $MVN_SETTINGS -o clean install -P $profile -Dsvn.revision=$revision -Dbuild.date=$BUILD_ID
  checkrv $? "maven clean install geoserver/web/app ($profile profile)"
  popd

  pushd dashboard
  $MVN -s $MVN_SETTINGS -o clean install -P $profile -Dsvn.revision=$revision -Dbuild.date=$BUILD_ID
  checkrv $? "maven clean install dashboard ($profile profile)"
  popd

  $MVN -s $MVN_SETTINGS -P $profile -o assembly:attached
  checkrv $? "maven assembly ($profile profile)"
}

#
# function to copy over build artifacts
# copy_artifacts [profile]
#
function copy_artifacts {
  local prefix=""
  local counter=0

  if [ ! -z $1 ]; then
    prefix=-$1
  fi

  pushd target/$1
  for x in $artifacts
  do
    if [ -e opengeosuite${prefix}-*-${x}.zip ]; then
       echo "copying opengeosuite${prefix}-*-${x}.zip"
       cp opengeosuite${prefix}-*-${x}.zip $dist/opengeosuite${prefix}-$id-r$revision-${x}.zip
       cp opengeosuite${prefix}-*-${x}.zip $dist/opengeosuite${prefix}-$id-latest-${x}.zip
       let counter=counter+1
    fi
  
    if [ -e opengeosuite${prefix}-*-${x}.tar.gz ]; then
      echo "copying opengeosuite${prefix}-*-${x}.tar.gz"
      cp opengeosuite${prefix}-*-${x}.tar.gz $dist/opengeosuite${prefix}-$id-r$revision-${x}.tar.gz
      cp opengeosuite${prefix}-*-${x}.tar.gz $dist/opengeosuite${prefix}-$id-latest-${x}.tar.gz
      let counter=counter+1
    fi
  done

  popd

  if [ $counter -eq 0 ]; then
    echo "no artifacts copied"
    exit 1
  fi
}

set -x

REPO_PATH=$GIT_BRANCH
dist=/var/www/suite/$REPO_PATH
if [ ! -e $dist ]; then
  mkdir -p $dist
fi
echo "dist: $dist"

artifacts="bin win mac ext war war-geoserver war-geoexplorer war-geoeditor war-geowebcache war-geoserver-jboss doc analytics control-flow importer readme dashboard-win32 dashboard-lin32 dashboard-lin64 dashboard-osx"
id=$(echo $REPO_PATH|sed 's/\//-/g')

# set up the maven repository for this particular branch/tag/etc...
MVN_SETTINGS_TEMPLATE=`pwd`/repo/build/settings.xml
pushd maven
if [ ! -d $REPO_PATH ]; then
  echo "Creating new maven repository at `pwd`/$REPO_PATH"
  mkdir -p $REPO_PATH
  sed "s#@PATH@#`pwd`/$REPO_PATH/repo#g" $MVN_SETTINGS_TEMPLATE > $REPO_PATH/settings.xml
  cp -R repo-template $REPO_PATH/repo
fi
popd

MVN_SETTINGS=`pwd`/maven/$REPO_PATH/settings.xml
export MAVEN_OPTS=-Xmx256m

# checkout the requested revision to build
cd repo
git checkout $REV

#if [ -d $REPO_PATH ]; then
#  cd $REPO_PATH
#  echo "updating $REPO_PATH"
#  svn update .
#  checkrv $? "svn update $REPO_PATH"
#else
#  mkdir -p $REPO_PATH
#  cd $REPO_PATH
#  echo "checking out $REPO_PATH"
#  svn checkout http://svn.opengeo.org/suite/$REPO_PATH .
#  checkrv $? "svn checkout $REPO_PATH"
#fi

# extract the revision number
revision=`git log --format=format:%H | head -n 1`
if [ "x$revision" == "x" ]; then
  echo "failed to get revision number from svn info"
  exit 1
fi

echo "building $revision with maven settings $MVN_SETTINGS"

# perform a full build
$MVN -s $MVN_SETTINGS -Dfull -Dmvn.exec=$MVN -Dmvn.settings=$MVN_SETTINGS -Dsvn.revision=$revision -Dbuild.date=$BUILD_ID clean install
checkrv $? "maven install"

$MVN -o -s $MVN_SETTINGS assembly:attached &&
checkrv $? "maven assembly"

$MVN -s $MVN_SETTINGS deploy -DskipTests &&
checkrv $? "maven deploy"

# build with the enterprise profile
profile_rebuild ee

# build with the cloud profile
#profile_rebuild cloud

# copy the new artifacts into place
copy_artifacts
copy_artifacts ee
#copy_artifacts cloud

#counter=0
#for x in $artifacts
#do
#  if [ -e target/opengeosuite-*-${x}.zip ]; then
#     echo "copying target/opengeosuite-*-${x}.zip"
#     cp target/opengeosuite-*-${x}.zip $dist/opengeosuite-$id-r$revision-${x}.zip
#     cp target/opengeosuite-*-${x}.zip $dist/opengeosuite-$id-latest-${x}.zip
#     let counter=counter+1
#  fi
#  
#  if [ -e target/opengeosuite-*-${x}.tar.gz ]; then
#    echo "copying target/opengeosuite-*-${x}.tar.gz"
#    cp target/opengeosuite-*-${x}.tar.gz $dist/opengeosuite-$id-r$revision-${x}.tar.gz
#    cp target/opengeosuite-*-${x}.tar.gz $dist/opengeosuite-$id-latest-${x}.tar.gz
#    let counter=counter+1
#  fi
#
#  CWD=`pwd` && cd target/ee
#  # enterprise
#  if [ -e opengeosuite-ee-*-${x}.zip ]; then
#     echo "copying target/opengeosuite-ee-*-${x}.zip"
#     cp opengeosuite-ee-*-${x}.zip $dist/opengeosuite-ee-$id-r$revision-${x}.zip
#     cp opengeosuite-ee-*-${x}.zip $dist/opengeosuite-ee-$id-latest-${x}.zip
#     let counter=counter+1
#  fi
#  
#  if [ -e opengeosuite-ee-*-${x}.tar.gz ]; then
#    echo "copying target/opengeosuite-ee-*-${x}.tar.gz"
#    cp opengeosuite-ee-*-${x}.tar.gz $dist/opengeosuite-ee-$id-r$revision-${x}.tar.gz
#    cp opengeosuite-ee-*-${x}.tar.gz $dist/opengeosuite-ee-$id-latest-${x}.tar.gz
#    let counter=counter+1
#  fi
#
#  cd $CWD
#done
#
#if [ $counter -eq 0 ]; then
#  echo "no artifacts copied"
#  exit 1
#fi

# copy the dashboard artifacts into place
pushd $dist
for f in `ls opengeosuite-*-dashboard-*.zip`; do
  f2=$(echo $f|sed 's/opengeosuite-//g'|sed 's/-dashboard//g'|sed 's/^/dashboard-/g') 
  mv $f $f2
done
popd

#dashboard_version=1.0.0
#pushd assembly/dashboard-${dashboard_version}-lin32
#zip -r9 $dist/dashboard-$id-r$revision-lin32.zip *
#popd
#pushd assembly/dashboard-${dashboard_version}-lin64
#zip -r9 $dist/dashboard-$id-r$revision-lin64.zip *
#popd
#pushd assembly/dashboard-${dashboard_version}-osx
#zip -r9 $dist/dashboard-$id-r$revision-osx.zip *
#popd
#pushd assembly/dashboard-${dashboard_version}-win32
#zip -r9 $dist/dashboard-$id-r$revision-win32.zip *
#popd

# clear out old artifacts
pushd $dist
for x in $artifacts; do
  ls -t | grep "opengeosuite-.*-$x.zip" | tail -n +7 | xargs rm -f
  ls -t | grep "opengeosuite-.*-$x.tar.gz" | tail -n +7 | xargs rm -f
done
for x in win32 lin32 lin64 osx; do
  ls -t | grep "dashboard-.*-$x.zip" | tail -n +7 | xargs rm -f
done
popd

# start_remote_job <url> <name> <profile>
function start_remote_job() {
   curl -k --connect-timeout 10 "$1/buildWithParameters?REPO_PATH=${REPO_PATH}&REVISION=${revision}&PROFILE=$3"
   checkrv $? "trigger $2 $3 with ${REPO_PATH} r${revision}"
}

# start the build of the OSX installer
start_remote_job http://10.52.11.40:8080/job/osx-installer "osx installer"

# start the build of the OSX installer (ee)
start_remote_job http://10.52.11.40:8080/job/osx-installer "osx installer" ee

# start the build of the Windows installer
start_remote_job http://10.52.11.58:8080/hudson/job/windows-installer "win installer"

# start the build of the Windows installer (ee)
start_remote_job http://10.52.11.58:8080/hudson/job/windows-installer "win installer" ee

# start the build of the Linux32 installer
#start_remote_job http://10.52.11.55:8080/job/linux32-installer "lin32 installer"

# start the build of the Linux64 installer
#start_remote_job http://10.52.11.57:8080/job/linux64-installer "lin64 installer"

# start the build of the 32 bit Ubuntu 10.4 package
#start_remote_job https://packaging-u1040-32.dev.opengeo.org/hudson/job/build "ubuntu 10.4 32 bit"

# start the build of the 64 bit Ubuntu 10.4 package
#start_remote_job https://packaging-u1040-64.dev.opengeo.org/hudson/job/build "ubuntu 10.4 64 bit"

# start the build of the 32 bit CenTOS 5.5 package
#start_remote_job https://packaging-c55-32.dev.opengeo.org/hudson/job/build "CentOS 5.5 32 bit"

# start the build of the 64 bit CenTOS 5.5 package
#start_remote_job https://packaging-c55-64.dev.opengeo.org/hudson/job/build "CentOS 5.5 64 bit"

echo "Done."

