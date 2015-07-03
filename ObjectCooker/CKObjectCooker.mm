// Copyright (c) 2014-2015, Cristian Kocza
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "CKObjectCooker.h"
#import <objc/runtime.h>
#import <objc/objc.h>

#include <string>
#include <vector>
#include <unordered_map>
#include <map>
#include <stdio.h>

using namespace std;

enum{
    CKObjectCookerRegisterKindClass = 0,
    CKObjectCookerRegisterKindInstance = 1,
    CKObjectCookerRegisterKindBlock = 2
};

class CKObjectCookerClassInfo{
public:
    Class theClass;
    const char *className;
    CKObjectCookerClassInfo(){}
    CKObjectCookerClassInfo(Class aClass, const char *className):theClass(aClass),className(className){}
};

class CKObjectCookerRegisterInfo: public CKObjectCookerClassInfo{
public:
    NSUInteger kind;
    id instance;
    id (^block)();
    NSUInteger options;
    CKObjectCookerRegisterInfo(){}
    CKObjectCookerRegisterInfo(Class aClass, const char *className):CKObjectCookerClassInfo(aClass,className){}
};

class CKObjectCookerDependencyInfo{
public:
    CKObjectCookerRegisterInfo *registerInfo;
    SEL setterSelector;
    void (*setter)(id,SEL,id);
};

@interface CKObjectCookerPlaceholder: NSObject{
    Class _actualClass;
    CKObjectCooker *_cooker;
    id _actualObject;
}
+ (id)placeholderWithActualClass:(Class)aClass withinCooker:(CKObjectCooker*)cooker;
@end

//hash and equal for char*, as stl doesn't default provide ones for this type
struct sdbm: public hash<const char*>{
    size_t operator()(const char* str) const{
        size_t h = 0;
        for (const char *it=str; *it; ++it){
            h = *it + (h << 6) + (h << 16) - h;
        }
        return h;
    }
};

struct streq: public equal_to<const char*>{
    bool operator()(const char *str1, const char *str2) const{
        return !strcmp(str1,str2);
    };
};

@interface CKObjectCooker(){
    unordered_map<const char*, CKObjectCookerRegisterInfo*, sdbm, streq> _registeredClasses;
    unordered_map<const char*, id, sdbm, streq> _singletonInstances;
    unordered_map<const char*, vector<CKObjectCookerDependencyInfo>*, sdbm, streq> _cachedDependencies;
}
@end

@implementation CKObjectCooker

- (id)init{
    if(self = [super init]){
        //registering myself, so that objects created by me can also have a dependncy on me
        Class myClass  = object_getClass(self);
        const char *className = class_getName(myClass);
        CKObjectCookerRegisterInfo *registerInfo = new CKObjectCookerRegisterInfo(myClass,className);
        registerInfo->kind = CKObjectCookerRegisterKindInstance;
        registerInfo->instance = self;
        _registeredClasses[className] = registerInfo;
    }
    return self;
}

- (void)dealloc{
    _registeredClasses.clear();
    _singletonInstances.clear();
    _cachedDependencies.clear();
}

#pragma mark -
#pragma mark DI

- (CKObjectCookerRegisterInfo*)buildClassInfo:(Class)aClass{
    if(!aClass){
        [[NSException exceptionWithName:@"CKObjectCookerException"
                                 reason:@"Cannot register a nil class"
                               userInfo:nil] raise];
    }
    
    if(class_isMetaClass(aClass)){
        [[NSException exceptionWithName:@"CKObjectCookerException"
                                 reason:@"Cannot register a metaclass"
                               userInfo:nil] raise];
    }
    
    if(aClass == [self class]){
        [[NSException exceptionWithName:@"CKObjectCookerException"
                                 reason:@"Cannot register the ObjectCooker"
                               userInfo:nil] raise];
    }
    
    char *className = (char*)class_getName(aClass);
    
    if(_registeredClasses.find(className) != _registeredClasses.end()){
        [[NSException exceptionWithName:@"CKObjectCookerException"
                                 reason:@"Class already registered"
                               userInfo:nil] raise];
    }
    return _registeredClasses[className] = new CKObjectCookerRegisterInfo(aClass,className);
}

- (CKObjectCookerRegisterInfo*)buildClassInfoForClassName:(NSString*)aClassName{
    const char *className = aClassName.UTF8String;
    if(_registeredClasses.find(className) != _registeredClasses.end()){
        [[NSException exceptionWithName:@"CKObjectCookerException"
                                 reason:@"Class already registered"
                               userInfo:nil] raise];
    }
    return _registeredClasses[className] = new CKObjectCookerRegisterInfo(nil,className);
}

- (void)registerAssembly:(CKObjectCookerAssembly*)assembly{
    for(NSString *className in assembly.instances){
        [self registerInstance:assembly.instances[className]
                      forClass:NSClassFromString(className)];
    }
    for(NSString *className in assembly.classes){
        [self registerClass:NSClassFromString(className)
                withOptions:[assembly.classes[className] intValue]];
    }
    for(NSString *className in assembly.posingClasses){
        [self registerClass:NSClassFromString(assembly.posingClasses[className])
              posingAsClass:NSClassFromString(className)];
    }
    for(NSString *className in assembly.blocks){
        [self registerBlock:assembly.blocks[className]
                   forClassName:className];
    }
}

- (void)registerClass:(Class)aClass withOptions:(NSUInteger)options{
    CKObjectCookerRegisterInfo *info = [self buildClassInfo:aClass];
    info->kind = CKObjectCookerRegisterKindClass;
    info->options = options;
}

- (void)registerClass:(Class)aClass posingAsClass:(Class)originalClass{
    CKObjectCookerRegisterInfo *info = [self buildClassInfo:originalClass];
    info->kind = CKObjectCookerRegisterKindClass;
    info->theClass = aClass;
    info->className = class_getName(aClass);
}

- (void)registerInstance:(id)instance forClass:(Class)aClass{   
    CKObjectCookerRegisterInfo *info = [self buildClassInfo:aClass];
    info->kind = CKObjectCookerRegisterKindInstance;
    info->instance = instance;
}

- (void)registerBlock:(id(^)())block forClassName:(NSString*)aClassName{
    CKObjectCookerRegisterInfo *info = [self buildClassInfoForClassName:aClassName];
    info->kind = CKObjectCookerRegisterKindBlock;
    info->block = [block copy];
}

- (id)alloc:(Class)aClass{
    if(!aClass){
        [[NSException exceptionWithName:@"CKObjectCookerException"
                                 reason:@"Cannot resolve a nil class"
                               userInfo:nil] raise];
    }
    return [self resolveInstanceForClass:aClass callInitIfNeeded:NO];
    //return [CKObjectCookerPlaceholder placeholderWithActualClass:aClass withinCooker:self];
}

- (id)resolve:(Class)aClass{
    return [self resolveInstanceForClass:aClass callInitIfNeeded:YES];
}

- (id)resolveInstanceForClass:(Class)aClass callInitIfNeeded:(BOOL)callInit{
    if(!aClass){
        [[NSException exceptionWithName:@"CKObjectCookerException"
                                 reason:@"Cannot resolve a nil class"
                               userInfo:nil] raise];
    }
    char *className = (char*)class_getName(aClass);
    id instance = nil;
    if(_registeredClasses.find(className) == _registeredClasses.end()){
        //class is not registered, simply alloc + init(if needed)
        instance = [aClass alloc];
        [self resolveDependenciesForObject:instance class:aClass className:className];
        if(callInit) instance = [instance init];
    }else{
        instance = [self resolveInstanceForRegisteredInfo:_registeredClasses[className] callInitIfNeeded:callInit];
    }
    return instance;
}

- (id)resolveInstanceForRegisteredInfo:(CKObjectCookerRegisterInfo*)info callInitIfNeeded:(BOOL)callInit{
    id instance = nil;
    if(info->kind == CKObjectCookerRegisterKindBlock){
        instance = info->block();
    }else if(info->kind ==  CKObjectCookerRegisterKindInstance){
        //instance registered for class, no other work needs to be done
        instance = info->instance; //an instance was set
    }else if(info->options & CKObjectCookerRegisterClassOptionSingleton){
        instance = _singletonInstances[info->className];
        if(!instance){
            //first time access of singleton instance, create it
            //and resolve it's dependencies
            instance = [info->theClass alloc];
            [self resolveDependenciesForObject:instance class:info->theClass className:info->className];
            instance = [instance init];
            _singletonInstances[info->className] = instance;
        }
    }else{
        //a class registered for this class
        instance = [info->theClass alloc];
        [self resolveDependenciesForObject:instance class:info->theClass className:info->className];
        //one arc inserted retain here
        if(callInit) instance = [instance init];
    }
    //another arc inserted retain here
    return instance;
}

//TODO: this is not multithreaded
//decorating the object with __unsafe_unretained to prevent ARC
//to insert extra unneeded retain/release calls
- (void)resolveDependenciesForObject:(__unsafe_unretained id)object
                               class:(Class)objectClass
                           className:(const char*)className{
    
    //cache the dependencies list, if not already cached
    if(_cachedDependencies.find(className) == _cachedDependencies.end()){
        vector<CKObjectCookerDependencyInfo> *dependencies = new vector<CKObjectCookerDependencyInfo>();
        //go through all classes from objectClass to the root class
        Class currentClass = objectClass;
        while(currentClass){
            //enumerate through all properties, find the ones that can be registered
            unsigned int propCount = 0;
            objc_property_t *props = class_copyPropertyList(currentClass, &propCount);
            for(int i=0;i<propCount;i++){
                objc_property_t prop = props[i];
                
                //custom string parsing on the property attributes
                //starting with 10.7 we would have property_copyAttributeValue
                //but SL doesn't have it, thus the code below
                char *attributes = strdup(property_getAttributes(prop));
                char *attributesEnd = attributes+strlen(attributes);
                char *type=NULL, *typeStart = NULL, *typeEnd = NULL;
                char *setterName=NULL, *setterNameStart = NULL, *setterNameEnd;
                
                //https://developer.apple.com/library/mac/documentation/cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101
                typeStart = attributes+1;
                typeEnd = strchr(typeStart, ',');
                if(!typeEnd) typeEnd = attributesEnd;
                
                type = strndup(typeStart, typeEnd-typeStart);
                size_t len = strlen(type);
                if(type[0] != '@' || len <= 4 || type[1] != '"' || type[len-1] != '"'){
                    free(type);
                    type = NULL;
                }else{
                    type[len-1] = 0; //getting rid of the ending quote
                }
                
                //if the class is not registered, skip it
                //TODO: if the property is readonly, skip it
                //type has the following form in case the property corresponds to an registered class
                //@"SomeClassName", so a type+2 needs to be used in order to get the un-decoracted class name
                if(type && _registeredClasses.find(type+2) != _registeredClasses.end()){
                    //find the setter name
                    setterNameStart = strstr(typeEnd,",S");
                    if(setterNameStart){
                        //we have a setter, use that one
                        setterNameStart += 2;
                        setterNameEnd = strchr(setterNameStart, ',');
                        if(!setterNameEnd) setterNameEnd = attributesEnd;
                        setterName = strndup(setterNameStart,setterNameEnd-setterNameStart);
                    }else{
                        //the default setXXX is used, compute it's name from the property name
                        char *propName = strdup(property_getName(prop));
                        if(propName[0] >= 'a' && propName[0] <= 'z')
                            propName[0] -= 'a' - 'A';
                        setterName = (char*)calloc(strlen(propName)+5, 1);
                        sprintf(setterName, "set%s:",propName);
                        free(propName);
                    }
                    
                    CKObjectCookerDependencyInfo dependencyInfo;
                    SEL sel = sel_registerName(setterName);
                    dependencyInfo.registerInfo = _registeredClasses[type+2];
                    dependencyInfo.setterSelector = sel;
                    dependencyInfo.setter = (void (*)(id,SEL,id))[object methodForSelector:sel];
                    dependencies->push_back(dependencyInfo);
                }
                if(attributes) free(attributes);
                if(type) free(type);
                if(setterName) free(setterName);
            }
            if(props) free(props);
            currentClass = class_getSuperclass(currentClass);
        }
        _cachedDependencies[className] = dependencies;
    }
    
    //dependency setting
    vector<CKObjectCookerDependencyInfo> *cachedDependencies =_cachedDependencies[className];
    vector<CKObjectCookerDependencyInfo>::iterator it;
    for(it=cachedDependencies->begin(); it != cachedDependencies->end(); it++){
        CKObjectCookerDependencyInfo dependencyInfo = *it;
        if(!dependencyInfo.setter) continue; //this should not happen, however better to be safe than sorry
        id value = [self resolveInstanceForRegisteredInfo:dependencyInfo.registerInfo callInitIfNeeded:YES];
        if(value){
            //TODO: check to see if altering the vtable affects the cached method
            //another retain here, due to the property set
            //using the direct function pointer for two reasons:
            //1. performance
            //2. performSelector:withObject: gives an ARC warning that a leak might occur due to the selector not
            //being known
            dependencyInfo.setter(object,dependencyInfo.setterSelector,value);
        }
    }
}

@end


@implementation  CKObjectCookerAssembly

- (NSDictionary*)instances{
    return nil;
}

- (NSDictionary*)classes{
    return nil;
}

- (NSArray*)posingClasses{
    return nil;
}

- (NSDictionary*)blocks{
    return nil;
}
@end

@implementation CKObjectCookerPlaceholder

+ (id)placeholderWithActualClass:(Class)aClass withinCooker:(CKObjectCooker*)cooker{
    //init is forwarded to the target object, only allocating
    CKObjectCookerPlaceholder *result = [self alloc];
    result->_actualClass = aClass;
    result->_cooker = cooker;
    return result;
}

//NSObject declares this method, so overwritting it as otherwise it won't go to the forwarding
//mechanism
- (id)init{
    //simply forward to the actual object creation and initialization
    return [_cooker resolveInstanceForClass:_actualClass callInitIfNeeded:YES];
};

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector{
    Method method = class_getInstanceMethod(_actualClass, aSelector);
    objc_method_description *desc = method?method_getDescription(method):nil;
    return desc?[NSMethodSignature signatureWithObjCTypes:desc->types]:nil;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation{
    //duplicating code for object creation in order to minimize the number
    //of methods implemented, to make sure all methods are forwarded
    if(!_actualObject){
        //this kind of objects are a result of [CKObjectCooker alloc:], so no init is needed
        _actualObject = [_cooker resolveInstanceForClass:_actualClass callInitIfNeeded:NO];
    }
    [anInvocation invokeWithTarget:_actualObject];
}

@end

/**
 * OSX < 10.7 doesn't have a strndup(), so we roll our own
 */
#ifdef __APPLE__
#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 1070
char *strndup(const char* s, size_t n) {
    size_t l = strlen(s);
    char *r = NULL;
    
    if (l < n)
        return strdup(s);
    
    r = (char*)malloc(n+1);
    if (r == NULL)
        return NULL;
    
    strncpy(r, s, n);
    r[n] ='\0';
    return r;
}
#endif
#endif
