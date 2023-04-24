import json
from url_methods import *
from constants import *
import lambda_multiprocessing

def validate_against_schema(value, definition):
    """
    Validate a piece of data with its asociated section in the schema

    Params:
      value: The data value to be evaluated
      params: The section of the schema with the definition of the field

    Returns: The return value for the piece of data either original or altered
             and an error string where None or empty means no error
    """
    if value is not None:
        data_type = definition.get("type")
        if data_type == "string":
            if not isinstance(value, str):
                if not isinstance(value, int):
                    return value, ERR_INVALID_STRING
                else:
                    value = str(value)
        elif data_type == "number":
            try:
                val = float(value)
            except:
                return value, ERR_INVALID_NUMBER
            minimum = definition.get("minimum")
            maximum = definition.get("maximum")
            if (val < minimum) or (val > maximum):
                return val, ERR_NUMBER_OUT_OF_RANGE
            return val, ""
        elif data_type == "array":
            if not isinstance(value,list):
                value = value.split(",")
            min_items = definition.get("minItems")
            items = definition.get("items")
            try:
                m_items = int(min_items)
            except:
                m_items = 0
            # Match each item in the data list against the list in schema
            if isinstance(items, list):
                for i in range(m_items):
                    val, error = validate_against_schema(value[i], items[i])
                    if error != "":
                        value[i] = f"{value[i]} - {error}"
                    else:
                        value[i] = val
            else:
                # Match the data list against the type of list in
                for i in range(len(value)):
                    val, error = validate_against_schema(value[i], items)
                    if error != "":
                        value[i] = f"{value[i]} - {error}"
                    else:
                        value[i] = val
        else:
            error = ERR_UNEXPECTED_SCHEMA_TYPE

    return value, ""

def get_data_layer(schema, data):
    """
    Go down through the layers of data to reach the data level
    based on the schema on each service

    Params:
      schema: The schema with the data structure needed
      data: The raw data read from the service

    Returns: The the section of the schema for the data transformation and
             the layer of data where is the required information 
    """
    schema_out = schema.get("lookup").get("out")
    structure = schema_out.get("structure")
    if structure.get("type")=="dict":
        key = structure.get("key")
        data_fields_layer = data.get(key)
    else:
        data_fields_layer = data
    schema_fields_layer = schema_out.get("data")
    return schema_fields_layer, data_fields_layer

def apply_out_api_pool(item_tuple):
    """
    Validate the data item against the output-api-schema

    Params:
      item_tuple: To be processed in parallel
        schema_items: list with all the output items
        schema_required: list with all required items
        item: the item item data to be validated

    Returns: The item affected by the model where either absent default values
             or data errors are point out 
    """
    schema_items, schema_required, item = item_tuple
    for key in schema_items:
        value = item.get(key)
        # Validate required parameters
        if (key in schema_required) and (value is None):
            value = ERR_ATTRIBUTE_NOT_FOUND
            item[key] = value
        else:
            # Validate value against schema
            key_definition = schema_items.get(key)
            val, schema_error = validate_against_schema(value, \
                                                        key_definition)
            if schema_error:
                item[key] = f"{value} - {schema_error}"
            else:
                item[key] = val
    return item

def adapt_to_model(service, model, schema_layer, item):
    """
    Extract the required information from each item based on the service model

    Params:
      service: The name of the service to be added at the begging of each item
      model: The model schema with tables to extract from
      schema_layer: The layer from the schema to apply as model for the item
      item: The item to be affected by the model

    Returns: A restructured new item matching the output requirements
    """
    list_to_process=[]
    output_item = {"key": service}
    # Start each record with 'key:service' to match the out-api-schema
    for key in schema_layer:
        schema = schema_layer.get(key)
        list_to_process.append((key, schema, item, model))

    num =len(list_to_process)
    with lambda_multiprocessing.Pool(num) as process:
        items = process.map(apply_schema_by_field, list_to_process)
    for item in items:
        output_item.update(item)
    return output_item

def items_from_service(service, model, schema_items, schema_required, load):
    """
    Based on the output schema and api-out schema, returns the formated
    data using multiprocessing to accelerate the task

    Params:
      service: The name of the service to put it ahead of the item's data
      model: The model schema with tables to extract from
      schema_items: the section of the out-api schema to process the data layer
      schema_required: The section of the out-api schema to validate the
                       prescence of the required field in the data layer
      load: the section of the item where the data can be extracted from

    Returns: A single instance containing all the
    schemas, each readable through its own key
    """
    list_to_process = []
    schema = model.get_schema()
    schema_layer, data_layer = get_data_layer(schema, load)
    #multiproces for the first function
    for data_item in data_layer:
        item = adapt_to_model(service, model, schema_layer, data_item)
        # Apply the 'generic' out-api-schema to the item
        list_to_process.append((schema_items, schema_required, item))
    num =len(list_to_process)
    with lambda_multiprocessing.Pool(num) as process:
        loads = process.map(apply_out_api_pool, list_to_process)
    return loads

def get_from_schema(schema, item):
    """
    Get the data value asociated with an specific field from a data item

    Params:
      schema: The schema or field name
      item: the data record
    Returns:
        The field value from the record if the field exists in the data item.
    """
    if schema is None:
        return None
    fields=schema.split(".")
    while len(fields) > 0:
        field = fields.pop(0)
        if field not in item:
            return None
        item = item.get(field)
        if item == "":
            return None
    return item

def get_from_array(schema, lookup, item):
    """
    Get the data value asociated with an specific field from an array of items

    Params:
      schema: The schema or field name
      lookup: the section of schema that defines the rules to extract the value
              from item
      item: the data record
    Returns:
        The field value from the array
    """
    item_array = get_from_schema(schema, item)
    ndx = int(lookup.get("field"))
    return item_array[ndx]

def get_from_dictionary(schema, item, model):
    """
    Based on the schema select and apply the method to use for the data
    adquisition from the item

    Params:
      schema: The schema that defines the adquisition rules
      item: the data record
      model: The model schema with tables to extract from
    Returns:
        The field value from item
    """
    field = schema.get("field")
    lookup = schema.get("lookup")
    if field == "":
        return NULL
    if not lookup:
        return  get_from_schema(field, item)
    else:
        schema_type = lookup.get("type")
        if schema_type == "table":
            return  model.get_from_table(field ,item)
        elif schema_type == "array":
            return  get_from_array(field, lookup, item)
        elif schema_type == "url":
            return  get_from_url(schema, item)
        else:
            return  ERR_UNEXPECTED_SCHEMA_TYPE

def apply_schema_by_field(parameters_tuple):
    """
    Extract the required information from each item based on the service model

    Params:
      parameters_tuple: To be processed in parallel
        key: The key of the field in the model
        schema: The schema of transformation for that field
        item: The data field to be obtained based on the schema
        model: The model schema with tables to extract from

    Returns: A restructured new item matching the output requirements
    """
    key, schema, item, model = parameters_tuple
    if isinstance(schema,dict):
        return {key: get_from_dictionary(schema, item, model)}
    elif isinstance(schema,list):
        list_for_field = []
        for item_schema in schema:
            list_for_field.append(get_from_dictionary(item_schema, item, model))
        return {key: list_for_field}
    else:
        return {key: ERR_UNEXPECTED_SCHEMA_TYPE}
