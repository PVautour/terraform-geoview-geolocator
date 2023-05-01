import json
from requests import Request, Session
import asyncio

def get_from_field(field, item):
    """
    Get the data value asociated with an specific field from a data item

    Params:
      field: The field name
      item: the data record
    Return:
        The field value from the record if the field exists in the data item.
    """
    if field is None or field not in item:
        return None
    return item.get(field)

def get_url_from_field(schema, data):
    """
    Get the url asociated with an specific field based on the schema provided

    Params:
      schema: The schema with the path to get access to the url
      data: the data structure where the url can be found
    Return: the field value asociated with
    """
    field = schema.get("field")
    url = schema.get("lookup").get("url")
    # Modify the url with the href at the bottom of the fields
    fields_list = field.split(".")
    href = data.get(fields_list[0]). \
                get(fields_list[1]). \
                get(fields_list[2]). \
                get(fields_list[3])
    return url.replace("_URL_", href)

def get_from_url(schema, data):
    """
    Get the data value asociated with an specific field from a REST response

    Params:
      schema: The schema defintion to access to the url
      data: the data structure where the url can be found
    Return: from a valid REST response, extracts the value from the asociated
             attribute.
    """
    field = schema.get("lookup").get("field")
    url = get_url_from_field(schema, data)
    load = url_request(url, {})
    return get_from_field(field, load)

def replace_url_with_params(url, params, params_list):
    """
    Replace and Return the parameters embedded in the url with a valid set
    of values

    Params:
      url: The url to be affected
      params: The list of parameters to be replace in the url
      params_list: The list of query parameters where to search for the
                   replacent to params
    Return: The url whit the original parameters are replaced with the
             asociated values.
    """
    for param in params:
        param_match = "_"+param.upper()+"_"
        replace_with = params_list.pop(params.get(param))
        url = url.replace(param_match, replace_with)
    return url

def assemble_url(schema, params):
    """
    Builds the url by matching the parameters against the schema

    Params:
      schema: The schema with the rules to assemble the url and parameters
      params: The list of parameters to be used to build the url

    Return: The assembled url including parameters as is required by the
             service schema.
    """
    # 1. Extract url and parameters from json
    url = schema.get("url")
    url_params = schema.get("urlParams")
    # 2. Parameters to modify the url
    if url_params:
        url = replace_url_with_params(url, url_params, params)
    # 3. lookup in parameters to replace with
    qry_params_dict = params
    lookup_in = schema.get("lookup").get("in")
    if lookup_in:
        for in_param in lookup_in:
            if in_param in params:
                qry_params_dict[lookup_in.get(in_param)] = params.pop(in_param)
    # 4. static parameters
    static_params = schema.get("staticParams")
    if static_params:
        qry_params_dict.update(static_params)
    return url, qry_params_dict

def url_request(url, params):
    """
    Calls a REST service passing the url

    Params:
      url: The url for the REST call
      params: The params to pass along with the url

    Return: The response from the call.
    """
    s = Session()
    request = Request('GET', url, params=params)
    prepared_request = request.prepare()
    query_response = s.send(prepared_request)
    json_response = query_response.json()
    return json_response