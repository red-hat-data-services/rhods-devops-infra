import datetime
import json
import time

import boto3
import os
import smartsheet
import re
class jira_manager:
    def __init__(self):
        pass

    def build_cells(self, column_map: dict, release_version, rc_number):
        cells = []

        column_object = {}
        column_object['columnId'] = column_map['Task Name']
        column_object['value'] = f'{release_version} RC{rc_number} available for QE'
        cells.append(column_object)

        column_object = {}
        column_object['columnId'] = column_map['Duration']
        column_object['value'] = '1d'
        cells.append(column_object)

        column_object = {}
        column_object['columnId'] = column_map['Start']
        column_object['value'] = datetime.datetime.today().date().strftime('%Y-%m-%d')
        cells.append(column_object)

        # column_object = {}
        # column_object['columnId'] = column_map['Finish']
        # column_object['value'] = datetime.datetime.today().date().strftime('%Y-%m-%d')
        # cells.append(column_object)

        return cells

    def insert_current_RC_to_smartsheet(self, release_version, rc_number):
        column_map = {}
        smart = smartsheet.Smartsheet()
        # response = smart.Sheets.list_sheets()
        sheed_id = 2157923266416516
        sheet = smart.Sheets.get_sheet(sheed_id)
        for column in sheet.columns:
            column_map[column.title] = column.id
        print(column_map)

        smartsheet_new_data = []
        # process existing data
        existingRows = {row.id: row.cells[1].value for row in sheet.rows if row.cells[1].value == f'{release_version} RC available for QE'}
        print(existingRows)

        siblingId = None
        if existingRows:
            for key, value in existingRows.items():
                siblingId = key
                break
        if siblingId:
            rowObject = {}
            rowObject['siblingId'] = siblingId
            rowObject['cells'] = self.build_cells(column_map, release_version, rc_number)
            smartsheet_new_data.append(rowObject)

        if smartsheet_new_data:
            payload = json.dumps(smartsheet_new_data, indent=4)
            print(f'Adding RC{rc_number} to the smartsheet', payload)
            response = smart.Passthrough.post(f'/sheets/{sheed_id}/rows', payload)
            print(response)


if __name__ == '__main__':
    jira_manager().insert_current_RC_to_smartsheet('2.10', '1')