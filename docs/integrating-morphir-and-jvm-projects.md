
# JVM: Executing morphir-cli

This document specifies all the necessary steps required to execute morphir-cli commands in a JVM project.

## Introduction

When using morphir generated code in a JVM project, it is sometimes the case that you need to execute morphir commands as part of your build process. While there are many ways to achieve this, we'll talk about the preferred way.

> The morphir cli is written in TypeScript and executes in a node environment, which means that node must be installed to run any morphir-cli command.


## Execute npm scripts.

One of the ways, which is also the preferred way, you can achieve this is to setup *npm build scripts* in your morphir project that can be executed by as part of the your project build.

There are a few benefits of this approach:
-  Using npm build scripts ensures that the morphir version specified for the morphir project is used for compiling the *morphir IR*.
- It also helps to reduce additional scripting code that would have been written if done in your project's build tool

> **_Note!_**
> This is not a requirement for using Morphir, or using morphir-cli commands in a JVM project.

### Specifying npm scripts

Every node project must include a [package.json](https://docs.npmjs.com/cli/v9/configuring-npm/package-json) file which can contain a [scripts section](https://docs.npmjs.com/cli/v9/configuring-npm/package-json#scripts) and defines the available [npm](https://docs.npmjs.com/about-npm) scripts for that node project.

*Example*
```JSON
	{ 
		"name": "my-package",
		"version": "1.0",
		"scripts": {
		 "make": "morphir make -f",
		 "generate": "morphir scala-gen -o ./generated/src",
		 "build": "npm run make && npm run generate"
		}
	}
```

This is a simple  `package.json` file that defines three scripts:
- `make` - that can be run using `npm run make` and
- `generate` - that can be run using `npm run generate`.
- `build` - that can be run using `npm run build`.

## Examples

Here are a few examples with your favorite build tools that show execution of npm scripts.

### Maven Example

If you're using maven as your build tool for build tool, you can use [MojoHaus](https://www.mojohaus.org/) plugin to run executables.
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"  
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"  
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">  
    <modelVersion>4.0.0</modelVersion>

	<!-- other project configurations -->
	
	<build>
		<plugins>
			<!-- you can specify other-plugins -->
			
			<!-- using MojoHaus to run npm script -->
			<plugin>
				<groupId>org.codehaus.mojo</groupId>  
				<artifactId>exec-maven-plugin</artifactId>  
				<version>3.1.0</version>
				<execution>  
				    <id>morphir-build</id>  
				    <phase>generate-sources</phase>  
				    <goals>  
				        <goal>exec</goal>  
				    </goals>  
				    <configuration>  
					    <!-- we want to invoke npm executable -->
				        <executable>npm</executable>
						<!-- specify the directory of the morphir project -->  
				        <workingDirectory>${project.basedir}</workingDirectory>  
				        <!-- running our build script defined in out package.json -->
				        <arguments>  
				            <argument>run</argument>  
				            <argument>build</argument>
				        </arguments>  
				    </configuration>  
				</execution>
			</plugin>
			
			<!-- maybe some more plugins -->
		</plugins>
		
		<!-- maybe some more project configurations -->
	</build>
</project>
```