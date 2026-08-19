import assert from 'node:assert/strict'
import test from 'node:test'
import type { DirectoryRow } from '../src/lib/database.types.ts'
import { directoryTrustScore, filterDirectory, normalizeDirectoryRow } from '../src/services/directory.ts'

const base: DirectoryRow={
  directory_id:'1',source_type:'listing',source_id:'1',business_name:'Base',slug:'base',category:'services',subcategory:'consulting',city:'Atlanta',state:'GA',neighborhood:null,address:null,postal_code:null,short_description:'Useful verified service',website_url:'https://example.com',instagram_handle:null,phone:'4045550100',business_email:'team@example.com',image_url:'https://example.com/a.jpg',latitude:33.75,longitude:-84.39,rating:4.2,review_count:10,price_range:null,featured:false,ownership_status:'verified',owner_verified:true,tags:['local'],hours:null,service_area:null,specialties:['Consulting'],facebook_url:null,linkedin_url:null,tiktok_url:null,serves_customers_at_location:true,service_radius_miles:null,
}
const business=(overrides:Partial<DirectoryRow>={})=>normalizeDirectoryRow({...base,...overrides})

test('verified complete listing outranks a featured high-rating but unverified listing',()=>{
  const trusted=business({business_name:'Trusted',featured:false,rating:4.1,owner_verified:true,ownership_status:'verified'})
  const popular=business({directory_id:'2',business_name:'Popular',featured:true,rating:5,review_count:50000,owner_verified:false,ownership_status:'unverified',website_url:null,phone:null,business_email:null,short_description:null,image_url:null,specialties:[],tags:[]})
  assert.ok(directoryTrustScore(trusted)>directoryTrustScore(popular))
  assert.equal(filterDirectory([popular,trusted],{category:'all',query:'',sort:'recommended'})[0].business_name,'Trusted')
})

test('featured placement does not alter recommendation quality',()=>{
  const plain=business({featured:false})
  const paidFlag=business({featured:true})
  assert.equal(directoryTrustScore(plain),directoryTrustScore(paidFlag))
})

test('proximity is capped at five points in recommended intelligence',()=>{
  const near={latitude:33.75,longitude:-84.39}
  const far=business({latitude:34.4,longitude:-85})
  const close=business({latitude:33.7501,longitude:-84.3901})
  assert.ok(directoryTrustScore(close,near)-directoryTrustScore(close)<=5)
  assert.ok(directoryTrustScore(far,near)-directoryTrustScore(far)<=5)
})
