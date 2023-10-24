from elasticsearch import Elasticsearch
from fastapi.encoders import jsonable_encoder
import os
# elasticsearch constants
ES_URL = 'search-ocp-qe-perf-scale-test-elk-hcm7wtsqpxy7xogbu72bor4uve.us-east-1.es.amazonaws.com'
ES_USERNAME = os.getenv('ES_USERNAME')
ES_PASSWORD = os.getenv('ES_PASSWORD')

class ElasticService:
    # todo add bulkhead pattern
    # todo add error message for unauthorized user

    def __init__(self,index="perf_scale_ci"):
        self.url = f'https://{ES_USERNAME}:{ES_PASSWORD}@{ES_URL}:443'
        print("index in search" + str(index))
        self.indice = index
        self.es = Elasticsearch(self.url)

    def post(self, query, indice=None):
        if indice is None:
            indice = self.indice
        print(jsonable_encoder(query))
        try: 
            response = self.es.search(
            index=indice,
            body=jsonable_encoder(query),
            size=10000)
        except Exception as e: 
            print('exception ' + str(e))
            response = []
        return response 

    def close(self):
        self.es.close()