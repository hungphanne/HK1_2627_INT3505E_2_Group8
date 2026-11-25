"""Offline static checks for HotelGenie contracts; NOT an API implementation test."""
import json
from pathlib import Path
import yaml
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parent
ALLOWED_HTTP = {'get','post','patch','put','delete','head','options','trace'}
for filename in ('openapi-public.yaml', 'openapi-internal.yaml'):
    spec = yaml.safe_load((ROOT / filename).read_text(encoding='utf8'))
    assert spec['openapi'] == '3.0.3'
    assert spec['paths']
    schemas = spec['components']['schemas']
    for path, methods in spec['paths'].items():
        assert path.startswith('/api/v1/') or path.startswith('/internal/v1/')
        for method, op in methods.items():
            assert method in ALLOWED_HTTP
            assert op.get('operationId') and op.get('tags') and op.get('responses')
    refs=[]
    def walk(o):
        if isinstance(o,dict):
            for k,v in o.items():
                if k=='$ref':refs.append(v)
                else:walk(v)
        elif isinstance(o,list):
            for v in o:walk(v)
    walk(spec)
    for ref in refs:
        assert ref.startswith('#/components/schemas/'), ref
        assert ref.rsplit('/',1)[-1] in schemas, ref
    print(f'PASS parse/ref: {filename}; {sum(len(x) for x in spec["paths"].values())} operations')
for file in sorted((ROOT/'events').glob('*.schema.json')):
    schema=json.loads(file.read_text(encoding='utf8'))
    Draft202012Validator.check_schema(schema)
    print(f'PASS event JSON Schema: {file.name}')
example=json.loads((ROOT/'examples'/'review-submitted.event.json').read_text(encoding='utf8'))
schema=json.loads((ROOT/'events'/'review.submitted.schema.json').read_text(encoding='utf8'))
Draft202012Validator(schema,format_checker=FormatChecker()).validate(example)
print('PASS review submitted example against schema')
print('NOTE: structural/static check only; no HTTP server, Redis, Spectral or OpenAPI semantic validation executed.')
