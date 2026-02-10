#!/usr/bin/env node

const k8s = require('@kubernetes/client-node');

async function testK8sAPI() {
    console.log('Testing Kubernetes API calls...');
    
    try {
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        console.log('Testing listNamespace()...');
        const namespacesResponse = await k8sApi.listNamespace();
        console.log('✅ listNamespace() SUCCESS:', namespacesResponse.body.items.length, 'namespaces found');
        
        console.log('Testing listNamespacedPod()...');
        const podsResponse = await k8sApi.listNamespacedPod({
            namespace: 'loco',
            labelSelector: 'app.kubernetes.io/component=emulator'
        });
        console.log('✅ listNamespacedPod() SUCCESS:', podsResponse.body.items.length, 'pods found');
        
    } catch (error) {
        console.error('❌ ERROR:', error.message);
        console.error('Stack:', error.stack);
    }
}

testK8sAPI();
