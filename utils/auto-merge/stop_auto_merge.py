import re
import os
from datetime import datetime, timedelta
import smartsheet
import argparse

import yaml


class stop_auto_merge:
    def __init__(self):
        pass

    def get_code_freeze_dates(self):
        column_map = {}
        smart = smartsheet.Smartsheet()
        # response = smart.Sheets.list_sheets()
        sheed_id = os.getenv('BUILD_SHEET_ID')
        sheet = smart.Sheets.get_sheet(sheed_id)
        for column in sheet.columns:
            column_map[column.title] = column.id
        # print(column_map)
        # 0       1           2           3           4
        # comment task name   duration    start date  end date

        # process existing data
        codeFreezeDates = {
            row.cells[1].value: datetime.strptime(row.cells[3].value, '%Y-%m-%dT%H:%M:%S').date() 
            for row in sheet.rows 
            if row.cells[3].value 
                and row.cells[1].value 
                and re.search(r'code[\s-]*freeze', str(row.cells[1].value), re.IGNORECASE)
        }
        print('codeFreezeDates', codeFreezeDates)
        return codeFreezeDates
    def get_release_to_be_removed(self):
        dates_to_search = []
        release_to_be_removed = ''
        if datetime.today().date().weekday() != 4:
        # if datetime.today().date().weekday() != 3:
            dates_to_search.append(datetime.today().date())
        if datetime.today().date().weekday() == 0:
        # if datetime.today().date().weekday() == 4:
            dates_to_search.append(datetime.today().date() - timedelta(days=3))
        codeFreezeDates = self.get_code_freeze_dates()
        for event, dt in codeFreezeDates.items():
            if dt in dates_to_search:

                capture = re.search('2.([0-9]{1,2})[a-zA-Z\s]{1,20}', event)
                if capture:
                    release_to_be_removed = f'rhoai-2.{capture.group(1)}'
                    break
                else:
                    print(f"warning: Event '{event}' on '{dt}' does not appear to be a minor (2.Y) release. Skipping.")

        print('release_to_be_removed', release_to_be_removed)
        print('dates_to_search', dates_to_search)
        return release_to_be_removed

    def update_release_map(self, release_to_be_removed):
        release_map = yaml.load(open('src/config/releases.yaml'))
        if release_to_be_removed:
            print(f'removing {release_to_be_removed} from the config')
            if release_to_be_removed in release_map['releases']:
                release_map['releases'].remove(release_to_be_removed)
        # If there are no releases, ensure it remains an empty list
        if release_map['releases'] is None:
            release_map['releases'] = []
            print('release_map', release_map)
        yaml.dump(release_map, open('src/config/releases.yaml', 'w'))



if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', default='DEFAULT', required=False, help='Release to be removed from the auto-merge config', dest='release')
    args = parser.parse_args()
    sam = stop_auto_merge()
    release_to_be_removed = args.release if args.release and args.release != 'DEFAULT' else sam.get_release_to_be_removed()
    with open('RELEASE_TO_BE_REMOVED' ,'w') as RELEASE_TO_BE_REMOVED:
        RELEASE_TO_BE_REMOVED.write(release_to_be_removed)
    sam.update_release_map(release_to_be_removed)
