from celery import shared_task, group, chord
from .utils.wazo_instance import WazoClient
from .models import WazoUserCache
import os
import logging

logger = logging.getLogger(__name__)

@shared_task
def process_user_batch(users_data, hostname):
    users_batch = [
        WazoUserCache(username=user.get("username"), platform_hostname=hostname)
        for user in users_data
    ]
    WazoUserCache.objects.bulk_create(users_batch, ignore_conflicts=True)
    return len(users_batch)

@shared_task
def get_wazo_node_users(node_number):
    hostname = os.environ.get(f'platform_node{node_number}_hostname')
    client_id = os.environ.get(f'platform_node{node_number}_client_id')
    client_secret = os.environ.get(f'platform_node{node_number}_client_secret')
    
    if not all([hostname, client_id, client_secret]):
        return {'error': f'Missing credentials for node {node_number}', 'processed': 0}
    
    wazo_instance_client = WazoClient(hostname, client_id, client_secret)
    
    limit = 200
    offset = 0
    all_batches = []
    
    while True:
        result_users = wazo_instance_client.get_users(params={'limit': limit, 'offset': offset})
        
        total = result_users.get("total", 0)
        items = result_users.get("items", [])
                
        if items:
            all_batches.append(items)
        
        offset += len(items)
        
        if offset >= total or not items:
            break
        
    if all_batches:
        batch_jobs = group(
            process_user_batch.s(batch, hostname) 
            for batch in all_batches
        )
        batch_jobs.apply_async()
    
    return {
        'node': node_number,
        'hostname': hostname,
        'batches': len(all_batches),
        'total_users': sum(len(batch) for batch in all_batches)
    }

@shared_task
def get_all_wazo_users():
    # nodes = [10]
    nodes = [10, 11, 12, 13]
    
    node_jobs = group(
        get_wazo_node_users.s(node) 
        for node in nodes
    )
    node_jobs.apply_async()
    
    return {'status': 'started', 'nodes': nodes}