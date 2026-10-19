package com.swarnos;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;
import org.springframework.stereotype.Repository;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.RestController;

/**
 * Layering of every module: api (controllers, DTOs) -> service (business rules)
 * -> repository (SQL) and domain (entities and pure rules).
 */
@AnalyzeClasses(packages = "com.swarnos", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

    @ArchTest
    static final ArchRule controllersLiveInTheApiLayer =
            classes().that().areAnnotatedWith(RestController.class).should().resideInAPackage("..api..");

    @ArchTest
    static final ArchRule repositoriesLiveInTheRepositoryLayer =
            classes().that().areAnnotatedWith(Repository.class).should().resideInAPackage("..repository..");

    @ArchTest
    static final ArchRule businessServicesLiveInTheServiceLayer =
            classes().that().areAnnotatedWith(Service.class).should().resideInAnyPackage("..service..", "com.swarnos.security");

    @ArchTest
    static final ArchRule apiDoesNotTouchTheDatabase =
            noClasses().that().resideInAPackage("..api..")
                    .should().dependOnClassesThat().resideInAnyPackage("..repository..", "..common.persistence..");

    @ArchTest
    static final ArchRule servicesDoNotDependOnTheApi =
            noClasses().that().resideInAPackage("..service..").should().dependOnClassesThat().resideInAPackage("..api..");

    @ArchTest
    static final ArchRule repositoriesHoldNoBusinessLogic =
            noClasses().that().resideInAPackage("..repository..")
                    .should().dependOnClassesThat().resideInAnyPackage("..service..", "..api..");

    @ArchTest
    static final ArchRule domainIsFrameworkFree =
            noClasses().that().resideInAPackage("..domain..")
                    .should().dependOnClassesThat().resideInAnyPackage("..service..", "..repository..", "..api..",
                            "org.springframework..", "java.sql..", "javax.sql..", "jakarta.servlet..");
}
