# @nolint

from typing import Any, Dict

class RecordSchema: pass

def asdict(obj: RecordSchema, *, dict_factory: Any = dict) -> Dict[str, Any]:
    """Return the fields of a RecordSchema instance as a new dictionary mapping
    field names to field values.
    """
    return _asdict_inner(obj, dict_factory)


def _asdict_inner(obj: Any, dict_factory: Any) -> Any:
    meta = getattr(obj, RecordSchema._META_PROP, {})

    if _is_dataclass_instance(obj):
        result = []
        for f in fields(obj):
            value = _asdict_inner(getattr(obj, f.name), dict_factory)
            field_meta = meta.get(f.name)
            if value is not None or (field_meta and field_meta.include_none):
                name_override = field_meta and field_meta.name
                result.append((name_override or f.name, value))
        return dict_factory(result)
    elif isinstance(obj, (list, tuple)):
        return type(obj)(_asdict_inner(v, dict_factory) for v in obj)
    elif isinstance(obj, DictRecord):
        result = []
        # item access in dict is already by serialized name
        for k, v in obj.items():
            value = _asdict_inner(v, dict_factory)
            field_meta = meta.get(k)
            if v is not None or (field_meta and field_meta.include_none):
                result.append((k, value))
        return dict_factory(result)
    elif isinstance(obj, MutableRecord):
        obj = obj.__dict__

        result = []
        for k, v in obj.items():
            value = _asdict_inner(v, dict_factory)
            field_meta = meta.get(k)
            if v is not None or (field_meta and field_meta.include_none):
                name_override = field_meta and field_meta.name
                result.append((name_override or k, value))
        return dict_factory(result)
    else:
        return obj


def asdict_test(obj):
    return asdict(obj)
